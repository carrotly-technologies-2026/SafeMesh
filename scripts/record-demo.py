#!/usr/bin/env python3
"""Record the DevEco emulator window, without recording the Windows desktop.

Windows + Python standard library only. FFmpeg is extracted from the user's
installed DevEco Studio distribution into the project's ignored .cache folder.
PrintWindow asks Emulator.exe to paint its own client area; no desktop DC or
screen-coordinate capture is used. Keep SafeMesh open in the emulator.
"""

import argparse
import ctypes as c
from ctypes import wintypes as w
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import zipfile


ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.cache' / 'recorder'


def prepare_encoder(studio):
    jars = sorted((studio / 'plugins' / 'harmony' / 'lib').glob(
        'ffmpeg-*-windows-x86_64.jar'))
    if not jars:
        raise RuntimeError('No bundled FFmpeg JAR. Set --studio to DevEco Studio.')
    CACHE.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(jars[-1]) as archive:
        for member in archive.namelist():
            name = Path(member).name
            if (member.startswith('org/bytedeco/ffmpeg/windows-x86_64/')
                    and name.endswith(('.exe', '.dll'))
                    and not name.startswith('jni')):
                target = CACHE / name
                # Do not overwrite DLLs loaded by another recording process.
                if not target.exists():
                    target.write_bytes(archive.read(member))
    encoder = CACHE / 'ffmpeg.exe'
    if not encoder.is_file():
        raise RuntimeError('The Studio JAR did not contain ffmpeg.exe.')
    return encoder


class BitmapHeader(c.Structure):
    _fields_ = [('size', w.DWORD), ('width', w.LONG), ('height', w.LONG),
                ('planes', w.WORD), ('bitcount', w.WORD),
                ('compression', w.DWORD), ('sizeimage', w.DWORD),
                ('x', w.LONG), ('y', w.LONG), ('used', w.DWORD),
                ('important', w.DWORD)]


class EmulatorCapture:
    def __init__(self, requested_pid=0):
        self.user = c.WinDLL('user32', use_last_error=True)
        self.gdi = c.WinDLL('gdi32', use_last_error=True)
        self.kernel = c.WinDLL('kernel32', use_last_error=True)
        self.user.SetProcessDPIAware()
        self.user.GetDC.argtypes = [w.HWND]
        self.user.GetDC.restype = w.HDC
        self.user.ReleaseDC.argtypes = [w.HWND, w.HDC]
        self.user.GetClientRect.argtypes = [w.HWND, c.POINTER(w.RECT)]
        self.user.IsWindow.argtypes = [w.HWND]
        self.user.IsWindowVisible.argtypes = [w.HWND]
        self.user.IsIconic.argtypes = [w.HWND]
        self.user.PrintWindow.argtypes = [w.HWND, w.HDC, w.UINT]
        self.user.GetWindowThreadProcessId.argtypes = [w.HWND, c.POINTER(w.DWORD)]
        self.gdi.CreateCompatibleDC.argtypes = [w.HDC]
        self.gdi.CreateCompatibleDC.restype = w.HDC
        self.gdi.CreateCompatibleBitmap.argtypes = [w.HDC, c.c_int, c.c_int]
        self.gdi.CreateCompatibleBitmap.restype = w.HBITMAP
        self.gdi.SelectObject.argtypes = [w.HDC, w.HGDIOBJ]
        self.gdi.SelectObject.restype = w.HGDIOBJ
        self.gdi.GetDIBits.argtypes = [w.HDC, w.HBITMAP, w.UINT, w.UINT,
                                      c.c_void_p, c.c_void_p, w.UINT]
        self.gdi.DeleteObject.argtypes = [w.HGDIOBJ]
        self.gdi.DeleteDC.argtypes = [w.HDC]
        self.kernel.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
        self.kernel.OpenProcess.restype = w.HANDLE
        self.kernel.QueryFullProcessImageNameW.argtypes = [w.HANDLE, w.DWORD,
                                                          w.LPWSTR, c.POINTER(w.DWORD)]
        self.kernel.CloseHandle.argtypes = [w.HANDLE]
        candidates = []

        @c.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
        def visit(hwnd, _):
            if not self.user.IsWindowVisible(hwnd) or self.user.IsIconic(hwnd):
                return True
            pid = w.DWORD()
            self.user.GetWindowThreadProcessId(hwnd, c.byref(pid))
            if requested_pid and pid.value != requested_pid:
                return True
            process = self.kernel.OpenProcess(0x1000, False, pid.value)
            if not process:
                return True
            try:
                path = c.create_unicode_buffer(32768)
                size = w.DWORD(len(path))
                if not self.kernel.QueryFullProcessImageNameW(process, 0, path, c.byref(size)):
                    return True
                # Never accept an arbitrary window or the desktop as a fallback.
                if Path(path.value).name.lower() != 'emulator.exe':
                    return True
                rect = w.RECT()
                self.user.GetClientRect(hwnd, c.byref(rect))
                if rect.right >= 200 and rect.bottom >= 300:
                    candidates.append((hwnd, pid.value, rect.right, rect.bottom))
            finally:
                self.kernel.CloseHandle(process)
            return True

        self.user.EnumWindows(visit, 0)
        if len(candidates) != 1:
            raise RuntimeError(f'Expected one visible Emulator.exe window; found {len(candidates)}. '
                               'Open the emulator or select its --pid.')
        self.hwnd, self.pid, self.width, self.height = candidates[0]
        self.dc = self.user.GetDC(self.hwnd)
        self.memory_dc = self.gdi.CreateCompatibleDC(self.dc)
        self.bitmap = self.gdi.CreateCompatibleBitmap(self.dc, self.width, self.height)
        if not self.dc or not self.memory_dc or not self.bitmap:
            raise RuntimeError('Could not allocate the window capture buffer.')
        self.original = self.gdi.SelectObject(self.memory_dc, self.bitmap)
        self.header = BitmapHeader(c.sizeof(BitmapHeader), self.width, -self.height,
                                   1, 32, 0, self.width * self.height * 4, 0, 0, 0, 0)
        self.buffer = c.create_string_buffer(self.width * self.height * 4)

    def frame(self):
        if (not self.user.IsWindow(self.hwnd) or not self.user.IsWindowVisible(self.hwnd)
                or self.user.IsIconic(self.hwnd)):
            raise RuntimeError('Emulator window closed, hidden or minimized; recording stopped.')
        rect = w.RECT()
        self.user.GetClientRect(self.hwnd, c.byref(rect))
        if (rect.right, rect.bottom) != (self.width, self.height):
            raise RuntimeError('Emulator window resized; recording stopped to preserve the crop.')
        # PW_CLIENTONLY | PW_RENDERFULLCONTENT; never reads the desktop framebuffer.
        if not self.user.PrintWindow(self.hwnd, self.memory_dc, 3):
            raise RuntimeError('Emulator PrintWindow failed; no desktop fallback is allowed.')
        self.gdi.SelectObject(self.memory_dc, self.original)
        lines = self.gdi.GetDIBits(self.memory_dc, self.bitmap, 0, self.height,
                                 self.buffer, c.byref(self.header), 0)
        self.gdi.SelectObject(self.memory_dc, self.bitmap)
        if lines != self.height:
            raise RuntimeError('Incomplete emulator frame.')
        return self.buffer.raw

    def close(self):
        self.gdi.SelectObject(self.memory_dc, self.original)
        self.gdi.DeleteObject(self.bitmap)
        self.gdi.DeleteDC(self.memory_dc)
        self.user.ReleaseDC(self.hwnd, self.dc)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--studio', type=Path,
                        default=Path(os.environ.get('DEVECO_CLI_STUDIO_PATH',
                                                   str(Path.home() / 'DevEcoStudio'))))
    parser.add_argument('--output', type=Path, default=ROOT / 'dist' / 'SafeMesh-demo.mp4')
    parser.add_argument('--duration', type=int, default=90)
    parser.add_argument('--fps', type=int, default=15)
    parser.add_argument('--pid', type=int, default=0, help='Select one Emulator.exe process.')
    parser.add_argument('--crop', help='Optional client pixels: left,top,width,height.')
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    if sys.platform != 'win32':
        parser.error('This recorder requires Windows.')
    if not 1 <= args.duration <= 600 or not 1 <= args.fps <= 30:
        parser.error('Duration must be 1..600 seconds and FPS must be 1..30.')
    encoder = prepare_encoder(args.studio)
    if args.prepare_only:
        print(f'Encoder ready: {encoder}', flush=True)
        return
    output = args.output.resolve()
    partial = output.with_name(output.stem + '.partial.mp4')
    if output.suffix.lower() != '.mp4' or output.exists() or partial.exists():
        raise RuntimeError('Choose a new .mp4 output; existing recordings are never overwritten.')
    output.parent.mkdir(parents=True, exist_ok=True)
    capture = EmulatorCapture(args.pid)
    process = None
    try:
        filters = []
        if args.crop:
            crop = [int(value) for value in args.crop.split(',')]
            if len(crop) != 4:
                raise ValueError('Crop requires left,top,width,height.')
            left, top, width, height = crop
            if (min(left, top) < 0 or min(width, height) < 2
                    or left + width > capture.width or top + height > capture.height):
                raise ValueError('Crop must fit entirely inside the emulator client area.')
            filters.append(f'crop={width}:{height}:{left}:{top}')
        filters.append('pad=ceil(iw/2)*2:ceil(ih/2)*2')
        command = [str(encoder), '-hide_banner', '-loglevel', 'warning', '-nostdin',
                   '-f', 'rawvideo', '-pixel_format', 'bgra', '-video_size',
                   f'{capture.width}x{capture.height}', '-framerate', str(args.fps),
                   '-i', 'pipe:0', '-an', '-vf', ','.join(filters),
                   '-c:v', 'libopenh264', '-b:v', '3M', '-pix_fmt', 'yuv420p',
                   '-movflags', '+faststart', '-n', str(partial)]
        process = subprocess.Popen(command, stdin=subprocess.PIPE,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        print(f'RECORDING: Emulator.exe PID {capture.pid}; {capture.width}x{capture.height}; '
              f'{args.fps} fps for {args.duration}s. Interact through devecocli in another terminal.',
              flush=True)
        started = time.monotonic()
        frames = args.duration * args.fps
        late_frames = 0
        for index in range(frames):
            remaining = started + index / args.fps - time.monotonic()
            if remaining > 0:
                time.sleep(remaining)
            elif remaining < -0.25:
                late_frames += 1
            if process.poll() is not None:
                raise RuntimeError('FFmpeg exited before recording completed.')
            process.stdin.write(capture.frame())
        process.stdin.close()
        process.wait(timeout=30)
        if process.returncode != 0:
            raise RuntimeError(f'FFmpeg failed with exit code {process.returncode}.')
        elapsed = time.monotonic() - started
        if late_frames > args.fps:
            raise RuntimeError('Capture fell behind real time. Retry at a lower --fps; '
                               'the incomplete recording has a .partial.mp4 name.')
        partial.rename(output)
        metadata = {'capture': 'Win32 PrintWindow, Emulator.exe client area only',
                    'audio': False, 'durationSeconds': args.duration, 'frames': frames,
                    'fps': args.fps, 'windowWidth': capture.width,
                    'windowHeight': capture.height, 'crop': args.crop,
                    'elapsedSeconds': round(elapsed, 2), 'lateFrames': late_frames}
        output.with_suffix('.capture.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
        print(f'RECORDED: {output} ({frames} live frames)', flush=True)
    finally:
        if process and process.poll() is None:
            if process.stdin and not process.stdin.closed:
                process.stdin.close()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
        capture.close()


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, OSError) as error:
        print(f'RECORDING FAILED: {error}', file=sys.stderr)
        sys.exit(1)
