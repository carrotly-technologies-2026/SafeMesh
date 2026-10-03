#!/usr/bin/env python3
"""Record three DevEco emulator windows side by side in one synchronized capture.

Windows + Python standard library only; reuses the PrintWindow capture and the
Studio-bundled FFmpeg from record-demo.py. Each frame captures A, B and C in the
same loop iteration, crops the phone screen and writes one composite stream, so
cross-device timing in the video is real. Nothing from the Windows desktop is read.

Find the Emulator.exe process IDs in PowerShell:
  Get-CimInstance Win32_Process -Filter "Name='Emulator.exe'" | Select ProcessId, CommandLine
"""

import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]


def load_recorder():
    spec = importlib.util.spec_from_file_location('record_demo', Path(__file__).with_name('record-demo.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--studio', type=Path,
                        default=Path(os.environ.get('DEVECO_CLI_STUDIO_PATH',
                                                   str(Path.home() / 'DevEcoStudio'))))
    parser.add_argument('--pids', type=int, nargs=3, required=True, metavar=('A', 'B', 'C'),
                        help='Emulator.exe process IDs for nodes A, B and C, left to right.')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--duration', type=int, default=240, help='Maximum seconds to record.')
    parser.add_argument('--fps', type=int, default=12)
    parser.add_argument('--crop', default='8,20,478,1030',
                        help='Phone screen inside each client area: left,top,width,height.')
    parser.add_argument('--stop-file', type=Path,
                        help='Stop early (and keep the recording) once this file exists.')
    args = parser.parse_args()
    if sys.platform != 'win32':
        parser.error('This recorder requires Windows.')
    if not 1 <= args.duration <= 600 or not 1 <= args.fps <= 30:
        parser.error('Duration must be 1..600 seconds and FPS must be 1..30.')
    if len(set(args.pids)) != 3:
        parser.error('Choose three different emulator processes.')
    left, top, width, height = [int(value) for value in args.crop.split(',')]
    recorder = load_recorder()
    encoder = recorder.prepare_encoder(args.studio)
    output = args.output.resolve()
    partial = output.with_name(output.stem + '.partial.mp4')
    if output.suffix.lower() != '.mp4' or output.exists() or partial.exists():
        raise RuntimeError('Choose a new .mp4 output; existing recordings are never overwritten.')
    output.parent.mkdir(parents=True, exist_ok=True)
    captures = [recorder.EmulatorCapture(pid) for pid in args.pids]
    process = None
    try:
        for capture in captures:
            if (min(left, top) < 0 or min(width, height) < 2 or left + width > capture.width
                    or top + height > capture.height):
                raise ValueError('Crop must fit inside every emulator client area.')
        if width % 2 or height % 2:
            raise ValueError('Crop width and height must be even for H.264.')
        command = [str(encoder), '-hide_banner', '-loglevel', 'warning', '-nostdin',
                   '-f', 'rawvideo', '-pixel_format', 'bgra', '-video_size',
                   f'{width * 3}x{height}', '-framerate', str(args.fps), '-i', 'pipe:0', '-an',
                   '-c:v', 'libopenh264', '-b:v', '6M', '-pix_fmt', 'yuv420p',
                   '-movflags', '+faststart', '-n', str(partial)]
        process = subprocess.Popen(command, stdin=subprocess.PIPE,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        started_epoch = time.time()
        started = time.monotonic()
        print(f'RECORDING_START epoch={started_epoch:.3f} pids={args.pids} '
              f'{width * 3}x{height} @ {args.fps} fps', flush=True)
        frames, late_frames = 0, 0
        stride = [capture.width * 4 for capture in captures]
        for index in range(args.duration * args.fps):
            if args.stop_file and args.stop_file.exists():
                break
            remaining = started + index / args.fps - time.monotonic()
            if remaining > 0:
                time.sleep(remaining)
            elif remaining < -0.25:
                late_frames += 1
            if process.poll() is not None:
                raise RuntimeError('FFmpeg exited before recording completed.')
            images = [capture.frame() for capture in captures]
            rows = []
            for row in range(top, top + height):
                for image, line in zip(images, stride):
                    begin = row * line + left * 4
                    rows.append(image[begin:begin + width * 4])
            process.stdin.write(b''.join(rows))
            frames += 1
        process.stdin.close()
        process.wait(timeout=60)
        if process.returncode != 0:
            raise RuntimeError(f'FFmpeg failed with exit code {process.returncode}.')
        elapsed = time.monotonic() - started
        if late_frames > max(args.fps, frames // 20):
            raise RuntimeError('Capture fell behind real time. Retry at a lower --fps; '
                               'the incomplete recording keeps its .partial.mp4 name.')
        partial.rename(output)
        metadata = {'capture': 'Win32 PrintWindow, three Emulator.exe client areas, one loop per frame',
                    'audio': False, 'startedEpoch': round(started_epoch, 3), 'frames': frames,
                    'fps': args.fps, 'crop': args.crop, 'pids': args.pids,
                    'elapsedSeconds': round(elapsed, 2), 'lateFrames': late_frames}
        output.with_suffix('.capture.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
        print(f'RECORDED: {output} ({frames} frames, {elapsed:.1f}s)', flush=True)
    finally:
        if process and process.poll() is None:
            if process.stdin and not process.stdin.closed:
                process.stdin.close()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
        for capture in captures:
            capture.close()


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, OSError) as error:
        print(f'RECORDING FAILED: {error}', file=sys.stderr)
        sys.exit(1)
