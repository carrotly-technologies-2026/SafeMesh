#!/usr/bin/env python3
"""Compose the SafeMesh demo video from the raw three-emulator capture.

Inputs (from narrate.py and drive.py):
  .cache/demo-video/voice/*.wav, durations.json   narration
  .cache/demo-video/raw.mp4, raw.events.json       capture and step times
  .cache/gallery-raw/                              screens for the "human-centric" scene

Steps: build a timeline (scenes, narration, captions, speed-up of the issuer's
typing), draw the bundled Kraków map pack as SVG, render every frame of
scenes.html in headless Edge/Chrome via Playwright, mix narration with short
synthesized sound cues and a quiet synthesized pad, then encode H.264 + AAC with
FFmpeg (imageio-ffmpeg's build). Also writes an .srt file with the captions and a .timeline.json.

  python scripts/demo-video/render.py --out dist/SafeMesh-demo.mp4
  python scripts/demo-video/render.py --preview 20,60,95   # stills only
"""

import argparse
import json
import math
import random
import re
import shutil
import subprocess
from pathlib import Path

import numpy as np
import soundfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WORK = ROOT / '.cache' / 'demo-video'
RATE = 24000
CROP_W, CROP_H = 478, 1030
SHOTS = [('en-light', '16-home-inbox', 'English · light'), ('pl-light', '17-message-detail', 'Polski · light'),
         ('en-dark', '02-map', 'English · dark'), ('pl-dark', '16-home-inbox', 'Polski · dark')]


def ffmpeg_exe():
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        return shutil.which('ffmpeg') or 'ffmpeg'


# ---------------------------------------------------------------- map ----
def map_svg():
    pack = json.loads((ROOT / 'entry' / 'src' / 'main' / 'resources' / 'rawfile' / 'map-pack.json').read_text(encoding='utf-8'))
    b = pack['bounds']
    W, H = 1920, 2174

    def xy(lat, lon):
        return (lon - b['west']) / (b['east'] - b['west']) * W, (b['north'] - lat) / (b['north'] - b['south']) * H

    def path(points):
        coords = [xy(lat, lon) for lat, lon in points]
        return 'M' + ' L'.join(f'{x:.1f} {y:.1f}' for x, y in coords)

    parts = []
    for kind, fill in (('park', 'rgba(152,217,180,0.13)'), ('water', 'rgba(110,170,180,0.30)')):
        d = ' '.join(path(a['points']) + ' Z' for a in pack['areas'] if a.get('kind') == kind and len(a['points']) > 2)
        parts.append(f'<path d="{d}" fill="{fill}" stroke="none"/>')
    d = ' '.join(path(r['points']) for r in pack['rivers'] if len(r['points']) > 1)
    parts.append(f'<path d="{d}" fill="none" stroke="rgba(110,170,180,0.55)" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>')
    styles = {'primary': ('rgba(216,245,138,0.22)', 3.4), 'secondary': ('rgba(216,245,138,0.18)', 2.8),
              'tertiary': ('rgba(216,245,138,0.15)', 2.2), 'pedestrian': ('rgba(216,245,138,0.20)', 1.8),
              'residential': ('rgba(244,246,240,0.10)', 1.3), 'living_street': ('rgba(244,246,240,0.09)', 1.2),
              'unclassified': ('rgba(244,246,240,0.09)', 1.2)}
    for kind, (stroke, width) in styles.items():
        d = ' '.join(path(s['points']) for s in pack['streets'] if s['kind'] == kind and len(s['points']) > 1)
        parts.append(f'<path d="{d}" fill="none" stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>')
    for point in pack['safePoints']:
        x, y = xy(point['lat'], point['lon'])
        parts.append(f'<circle class="sp" cx="{x:.1f}" cy="{y:.1f}" r="5.5" fill="#D8F58A" opacity="0"/>')
    cx, cy = xy(pack['center']['lat'], pack['center']['lon'])
    # Illustrative cell towers around the old town, and phones that form a mesh.
    for dx, dy in ((-560, -250), (390, -300), (-320, 270), (560, 210)):
        x, y = cx + dx, cy + dy
        rings = ''.join(f'<circle class="tw-ring" cx="{x:.0f}" cy="{y:.0f}" r="20" fill="none" stroke="#F4F6F0" stroke-width="2.5" opacity="0"/>' for _ in range(3))
        parts.append(f'<g class="tw">{rings}<g class="tw-icon" stroke="#F4F6F0" stroke-width="5" fill="none" stroke-linecap="round">'
                     f'<path d="M{x:.0f} {y - 10:.0f} V{y + 38:.0f} M{x - 16:.0f} {y + 38:.0f} L{x:.0f} {y - 4:.0f} L{x + 16:.0f} {y + 38:.0f}"/>'
                     f'<circle cx="{x:.0f}" cy="{y - 16:.0f}" r="6"/></g>'
                     f'<g class="tw-x" opacity="0" stroke="#FF9C86" stroke-width="6" stroke-linecap="round">'
                     f'<path d="M{x + 18:.0f} {y - 40:.0f} l22 22 M{x + 40:.0f} {y - 40:.0f} l-22 22"/></g></g>')
    rng = random.Random(7)
    phones = []
    while len(phones) < 30:
        x, y = cx + rng.uniform(-680, 680), cy + rng.uniform(-380, 380)
        if all(math.hypot(x - px, y - py) > 120 for px, py in phones):
            phones.append((x, y))
    links = set()
    for i, (x, y) in enumerate(phones):
        nearest = sorted(range(len(phones)), key=lambda j: math.hypot(phones[j][0] - x, phones[j][1] - y))[1:3]
        for j in nearest:
            links.add(tuple(sorted((i, j))))
    for i, j in sorted(links):
        (x1, y1), (x2, y2) = phones[i], phones[j]
        parts.append(f'<line class="ml" x1="{x1:.0f}" y1="{y1:.0f}" x2="{x2:.0f}" y2="{y2:.0f}" pathLength="400" '
                     f'stroke="#D8F58A" stroke-width="3" stroke-dasharray="400" stroke-dashoffset="400" opacity="0"/>')
    for x, y in phones:
        parts.append(f'<circle class="mp" cx="{x:.0f}" cy="{y:.0f}" r="7" fill="#D8F58A" opacity="0"/>')
    return ''.join(parts), (cx, cy)


# ------------------------------------------------------------ timeline ----
def split_caption(text, start, end, limit=105):
    if len(text) <= limit:
        return [{'start': start, 'end': end, 'text': text}]
    pieces = [p.strip() for p in re.split(r'(?<=[.;:])\s+', text) if p.strip()]
    chunks, current = [], ''
    for piece in pieces:
        if current and len(current) + 1 + len(piece) > limit:
            chunks.append(current)
            current = piece
        else:
            current = (current + ' ' + piece).strip()
    chunks.append(current)
    total = sum(len(c) for c in chunks)
    out, at = [], start
    for chunk in chunks:
        span = (end - start) * len(chunk) / total
        out.append({'start': round(at, 3), 'end': round(at + span, 3), 'text': chunk})
        at += span
    return out


def read_taps(log_path):
    """(phone, id) -> capture time of the tap, from drive.py's log; ('A', id, 'after') for the last one."""
    taps = {}
    if log_path.exists():
        for line in log_path.read_text(encoding='utf-8', errors='replace').splitlines():
            match = re.match(r'\s*([\d.]+)s ([ABC]) tap (\S+)', line)
            if match:
                at, phone, key = float(match.group(1)), match.group(2), match.group(3)
                taps.setdefault((phone, key), at)
                taps[(phone, key, 'after')] = at
    return taps


def build_timeline(voice, events, capture, taps):
    lines = {line['id']: line for line in json.loads((HERE / 'narration.json').read_text(encoding='utf-8'))}
    place = {}
    scenes = []

    def say(key, at):
        place[key] = round(at, 3)
        return at + voice[key]

    scenes.append({'id': 'cold', 'start': 0.0, 'end': 9.3, 'fade': 0.6})
    say('N01', 0.9)
    scenes.append({'id': 'title', 'start': 8.7, 'end': 19.5, 'fade': 0.6})
    say('N02', 9.6)
    how = {'id': 'how', 'start': 19.2, 'end': 37.4, 'fade': 0.5}
    scenes.append(how)
    say('N03', 19.6)
    say('N04', max(27.4, place['N03'] + voice['N03'] + 0.25))

    # Demo: the capture plays at 1x where something happens. Typing, navigation and scrolling are
    # compressed (with an on-screen speed badge); the last frame holds while the narration ends.
    v0 = 37.6
    tap = taps.get
    publish = tap(('A', 'publishAlert'), events['b_banner'] - 1.2)
    b_tab1 = tap(('B', 'tab1'), events['map'] + 5.5)
    a_back = tap(('A', 'backSettings', 'after'), events['nearlink'] + 1.3)
    a_check = tap(('A', 'checkNearLink'), events['nearlink_result'] - 1.5)
    plan = [
        (0.0, events['connect'], None, ''),
        (events['connect'], events['issuer'], None, ''),
        (events['issuer'], publish + 0.4, voice['N07'] + 0.9, 'while A signs in and types'),
        (publish + 0.4, events['move'] - 0.3, None, ''),
        (events['move'] - 0.3, events['c_route'] + 2.7, None, ''),
        (events['c_route'] + 2.7, events['forge'] - 0.5, 1.0, 'C opens Relay'),
        (events['forge'] - 0.5, events['map'], None, ''),
        (events['map'], b_tab1 + 0.3, 1.2, 'B opens the map'),
        (b_tab1 + 0.3, events['nearlink'], None, ''),
        (events['nearlink'], a_back + 1.0, None, ''),
        (a_back + 1.0, a_check - 0.3, 2.0, 'A scrolls to NearLink'),
        (a_check - 0.3, events['end'], None, ''),
    ]
    segments, speed = [], []
    at = v0
    for r0, r1, length, label in plan:
        if r1 <= r0:
            continue
        length = r1 - r0 if length is None else length
        segments.append({'r0': r0, 'r1': r1, 'v0': round(at, 3), 'v1': round(at + length, 3)})
        factor = (r1 - r0) / length
        if factor >= 1.5:
            speed.append({'v0': round(at, 3), 'v1': round(at + length, 3), 'factor': round(factor, 1), 'label': label})
        at += length

    def video(r):
        for s in segments:
            if r <= s['r1']:
                return s['v0'] + (r - s['r0']) * (s['v1'] - s['v0']) / (s['r1'] - s['r0'])
        return segments[-1]['v1']

    ev = {name: round(video(r), 3) for name, r in events.items()}
    ev['publish'] = round(video(publish), 3)
    say('N05', v0 + 0.3)
    say('N06', ev['connect'] + 0.1)
    say('N07', ev['issuer'] + 0.2)
    say('N08', ev['b_banner'] + 0.1)
    say('N09', video(events['move'] - 0.3))
    say('N10', ev['c_narration'])
    say('N11', ev['forge'])
    say('N12', ev['map'])
    narration_end = say('N13', ev['nearlink'])
    hold = max(0.0, narration_end + 1.2 - segments[-1]['v1'])
    last = events['end']
    segments.append({'r0': last, 'r1': last, 'v0': segments[-1]['v1'], 'v1': round(segments[-1]['v1'] + hold, 3)})
    ev['end'] = segments[-1]['v1']
    demo_end = ev['end'] + 0.4
    scenes.append({'id': 'demo', 'start': v0 - 0.5, 'end': demo_end, 'fade': 0.5})

    start = demo_end - 0.4
    split = say('N14', start + 0.5) + 0.4
    end = say('N15', split + 0.3) + 0.8
    scenes.append({'id': 'platform', 'start': start, 'end': end, 'fade': 0.5})
    start = end - 0.4
    end = say('N16', start + 0.4) + 1.0
    scenes.append({'id': 'incl', 'start': start, 'end': end, 'fade': 0.5})
    start = end - 0.4
    end = say('N17', start + 0.4) + 0.9
    scenes.append({'id': 'evidence', 'start': start, 'end': end, 'fade': 0.5})
    start = end - 0.4
    end = say('N18', start + 0.4) + 0.9
    scenes.append({'id': 'next', 'start': start, 'end': end, 'fade': 0.5})
    start = end - 0.4
    duration = say('N19', start + 0.7) + 4.2
    scenes.append({'id': 'outro', 'start': start, 'end': duration + 1, 'fade': 0.6})

    ordered = sorted(place.items(), key=lambda item: item[1])
    for (key, at), (_, following) in zip(ordered, ordered[1:] + [(None, duration)]):
        if at + voice[key] > following + 0.01:
            raise SystemExit(f'narration {key} overlaps the next line by {at + voice[key] - following:.2f}s')
    captions = []
    for key, at in ordered:
        captions += split_caption(lines[key]['caption'], at, at + voice[key] + 0.25)
    cues = [('powerdown', 3.0), ('chime', 9.1), ('ping', how['start'] + 3.4), ('ping', how['start'] + 9.4),
            ('ping', how['start'] + 12.8), ('reject', how['start'] + 15.3),
            ('whoosh', ev['publish']), ('ping', ev['b_banner']), ('whoosh', ev['links_bc']), ('ping', ev['c_banner']),
            ('whoosh', ev['inject']), ('reject', ev['rejected'])]
    return {'duration': round(duration, 3), 'scenes': scenes, 'narration': place, 'captions': captions, 'cues': cues,
            'platformSplit': round(split, 3),
            'demo': {'segments': segments, 'events': ev, 'fps': capture['fps'], 'frames': capture['frames'],
                     'cropWidth': CROP_W, 'cropHeight': CROP_H, 'speed': speed}}


# --------------------------------------------------------------- audio ----
def tone(freqs, length, decay, amplitude, sweep=None):
    t = np.arange(int(length * RATE)) / RATE
    wave = np.zeros_like(t)
    for f in freqs:
        if sweep:
            f_t = f * (sweep ** (t / length))
            wave += np.sin(2 * np.pi * np.cumsum(f_t) / RATE)
        else:
            wave += np.sin(2 * np.pi * f * t)
    attack = np.minimum(1, t / 0.006)
    return amplitude * wave / len(freqs) * attack * np.exp(-t / decay)


def cue(name):
    if name == 'ping':
        a = tone([1046.5], 0.5, 0.12, 0.30)
        b = tone([1568.0], 0.5, 0.14, 0.26)
        out = np.zeros(int(0.6 * RATE))
        out[:len(a)] += a
        out[int(0.07 * RATE):int(0.07 * RATE) + len(b)] += b
        return out
    if name == 'reject':
        return tone([196.0, 207.7], 0.45, 0.16, 0.42)
    if name == 'whoosh':
        n = int(0.45 * RATE)
        rng = np.random.default_rng(3)
        noise = np.convolve(rng.standard_normal(n), np.ones(24) / 24, mode='same')
        env = np.sin(np.linspace(0, np.pi, n)) ** 2
        return 0.10 * noise * env
    if name == 'powerdown':
        return tone([420.0, 630.0], 0.9, 0.35, 0.30, sweep=0.2)
    if name == 'chime':
        return tone([523.25, 659.25, 783.99, 1046.5], 2.2, 0.7, 0.24)
    raise ValueError(name)


def ambience(seconds):
    """A very quiet, slowly breathing A-major pad under the whole video (synthesized, no samples)."""
    t = np.arange(int(seconds * RATE)) / RATE
    pad = np.zeros_like(t)
    for i, f in enumerate((110.0, 164.81, 220.0, 277.18)):
        lfo = 0.6 + 0.4 * np.sin(2 * np.pi * (0.05 + 0.013 * i) * t + i)
        pad += lfo * (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 1.003 * t))
    fade = np.minimum(1, t / 3.0) * np.minimum(1, (seconds - t) / 3.5).clip(0, 1)
    return 0.012 * pad * fade


def mix_audio(timeline, voice_dir, out_wav):
    total = np.zeros(int((timeline['duration'] + 1) * RATE), dtype=np.float64)
    total[:int(timeline['duration'] * RATE)] += ambience(timeline['duration'])[:int(timeline['duration'] * RATE)]
    for key, at in timeline['narration'].items():
        samples, rate = soundfile.read(voice_dir / f'{key}.wav', dtype='float64')
        assert rate == RATE
        samples = samples / max(1e-6, np.max(np.abs(samples))) * 0.89
        i = int(at * RATE)
        total[i:i + len(samples)] += samples[:len(total) - i]
    for name, at in timeline['cues']:
        samples = cue(name)
        i = int(at * RATE)
        total[i:i + len(samples)] += samples[:len(total) - i]
    total = np.clip(total, -0.99, 0.99)
    soundfile.write(out_wav, total.astype(np.float32), RATE)


def write_srt(captions, path):
    def stamp(s):
        ms = int(round(s * 1000))
        return f'{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}'
    blocks = [f'{i}\n{stamp(c["start"])} --> {stamp(c["end"])}\n{c["text"]}\n' for i, c in enumerate(captions, 1)]
    path.write_text('\n'.join(blocks), encoding='utf-8')


# -------------------------------------------------------------- render ----
def prepare_frames(raw_video, frames_dir):
    if frames_dir.exists() and any(frames_dir.iterdir()):
        return
    frames_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run([ffmpeg_exe(), '-v', 'error', '-i', str(raw_video), '-q:v', '2', str(frames_dir / '%06d.jpg')], check=True)


def prepare_shots(gallery, shots_dir, required=True):
    shots_dir.mkdir(parents=True, exist_ok=True)
    result = []
    for variant, screen, label in SHOTS:
        source = gallery / variant / f'{screen}.png'
        target = shots_dir / f'{variant}-{screen}.jpg'
        if not source.exists():
            if required:
                raise SystemExit(f'missing {source}; run scripts/capture-gallery.py first')
            Image.new('RGB', (660, 1428), (40, 60, 52)).save(target)
        else:
            with Image.open(source) as image:
                image = image.convert('RGB').crop((0, 0, 1320, 2856)).resize((660, 1428), Image.LANCZOS)
                image.save(target, quality=92)
        result.append({'src': target.resolve().as_uri(), 'label': label})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--raw', type=Path, default=WORK / 'raw')
    parser.add_argument('--voice', type=Path, default=WORK / 'voice')
    parser.add_argument('--gallery', type=Path, default=ROOT / '.cache' / 'gallery-raw')
    parser.add_argument('--out', type=Path, default=ROOT / 'dist' / 'SafeMesh-demo.mp4')
    parser.add_argument('--fps', type=int, default=30)
    parser.add_argument('--channel', default='msedge')
    parser.add_argument('--preview', help='Comma-separated times: write PNG stills to .cache/demo-video/preview only.')
    parser.add_argument('--from-to', help='Render only this part, e.g. 60,75 (for checking audio and encoding).')
    args = parser.parse_args()

    voice = json.loads((args.voice / 'durations.json').read_text(encoding='utf-8'))
    events = json.loads(args.raw.with_suffix('.events.json').read_text(encoding='utf-8'))
    capture = json.loads(args.raw.with_suffix('.capture.json').read_text(encoding='utf-8'))
    timeline = build_timeline(voice, events, capture, read_taps(args.raw.with_suffix('.log')))
    svg, centre = map_svg()
    frames_dir = WORK / 'frames'
    prepare_frames(args.raw.with_suffix('.mp4'), frames_dir)
    timeline['demo']['frames'] = len(list(frames_dir.glob('*.jpg')))
    timeline['demo']['framePattern'] = frames_dir.resolve().as_uri() + '/%06d.jpg'
    timeline['shots'] = prepare_shots(args.gallery, WORK / 'shots', required=not (args.preview or args.from_to))
    timeline['mapSvg'] = svg
    timeline['mapCenter'] = centre
    (WORK / 'timeline.json').write_text(json.dumps({k: v for k, v in timeline.items() if k != 'mapSvg'}, indent=1),
                                        encoding='utf-8')

    from playwright.sync_api import sync_playwright
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel=args.channel)
        page = browser.new_page(viewport={'width': 1920, 'height': 1080})
        page.goto((HERE / 'scenes.html').resolve().as_uri())
        page.evaluate('tl => setup(tl)', timeline)
        page.evaluate('document.fonts.ready.then(() => true)')
        if args.preview:
            out = WORK / 'preview'
            out.mkdir(parents=True, exist_ok=True)
            for value in args.preview.split(','):
                t = float(value)
                page.evaluate('t => renderFrame(t)', t)
                page.screenshot(path=str(out / f'{t:07.2f}.png'))
                print('preview', t)
            browser.close()
            print(json.dumps({'duration': timeline['duration'], 'events': timeline['demo']['events'],
                              'speed': timeline['demo']['speed'], 'narration': timeline['narration'],
                              'scenes': timeline['scenes']}, indent=1))
            return
        args.out.parent.mkdir(parents=True, exist_ok=True)
        wav = WORK / 'mix.wav'
        mix_audio(timeline, args.voice, wav)
        write_srt(timeline['captions'], args.out.with_suffix('.srt'))
        first, last = 0, int(timeline['duration'] * args.fps)
        audio_offset = []
        if args.from_to:
            a, b = (float(v) for v in args.from_to.split(','))
            first, last = int(a * args.fps), int(b * args.fps)
            audio_offset = ['-ss', f'{a:.3f}']
        frames = last - first
        encoder = subprocess.Popen([ffmpeg_exe(), '-y', '-v', 'error', '-f', 'image2pipe', '-framerate', str(args.fps),
                                    '-c:v', 'mjpeg', '-i', '-', *audio_offset, '-i', str(wav),
                                    '-filter:a', 'loudnorm=I=-16:TP=-1.5:LRA=11', '-ar', '48000',
                                    '-vf', 'scale=in_range=pc:out_range=tv,format=yuv420p', '-color_range', 'tv',
                                    '-c:v', 'libx264', '-preset', 'slow', '-crf', '17',
                                    '-c:a', 'aac', '-b:a', '192k', '-ac', '2', '-shortest', '-movflags', '+faststart',
                                    '-metadata', 'title=SafeMesh demo (HackYeah 2026)', str(args.out)],
                                   stdin=subprocess.PIPE)
        for index in range(first, last):
            t = index / args.fps
            page.evaluate('t => renderFrame(t)', t)
            encoder.stdin.write(page.screenshot(type='jpeg', quality=94))
            if index % 300 == 0:
                print(f'frame {index}/{frames}', flush=True)
        encoder.stdin.close()
        if encoder.wait() != 0:
            raise SystemExit('FFmpeg failed')
        browser.close()
    (args.out.with_suffix('.timeline.json')).write_text(
        json.dumps({k: v for k, v in timeline.items() if k not in ('mapSvg', 'shots')}, indent=1), encoding='utf-8')
    print('wrote', args.out, f'{timeline["duration"]:.1f}s')


if __name__ == '__main__':
    main()
