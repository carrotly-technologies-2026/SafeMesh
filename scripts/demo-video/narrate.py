#!/usr/bin/env python3
"""Synthesize the demo video narration with Kokoro-82M, offline.

Model: Kokoro-82M v1.0 (Apache-2.0) through kokoro-onnx, voice af_heart. The model
files are downloaded once and are not part of the repository:
  https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
  https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin

  pip install kokoro-onnx soundfile
  python scripts/demo-video/narrate.py --models <folder with both files>

Writes one WAV per line of narration.json and voice/durations.json, which
drive.py uses to time the recording and render.py uses to place the audio.
"""

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--models', type=Path, required=True)
    parser.add_argument('--out', type=Path, default=ROOT / '.cache' / 'demo-video' / 'voice')
    parser.add_argument('--voice', default='af_heart')
    parser.add_argument('--speed', type=float, default=1.0)
    args = parser.parse_args()

    import numpy as np
    import soundfile
    from kokoro_onnx import Kokoro

    kokoro = Kokoro(str(args.models / 'kokoro-v1.0.onnx'), str(args.models / 'voices-v1.0.bin'))
    args.out.mkdir(parents=True, exist_ok=True)
    durations = {}
    for line in json.loads((HERE / 'narration.json').read_text(encoding='utf-8')):
        samples, rate = kokoro.create(line['speech'], voice=args.voice, speed=args.speed, lang='en-us')
        loud = np.where(np.abs(samples) > 0.01)[0]
        samples = samples[max(0, loud[0] - int(0.03 * rate)):loud[-1] + int(0.08 * rate)]
        soundfile.write(args.out / f'{line["id"]}.wav', samples, rate)
        durations[line['id']] = round(len(samples) / rate, 3)
        print(line['id'], durations[line['id']])
    (args.out / 'durations.json').write_text(json.dumps(durations, indent=1), encoding='utf-8')
    print('total', round(sum(durations.values()), 1), 's')


if __name__ == '__main__':
    main()
