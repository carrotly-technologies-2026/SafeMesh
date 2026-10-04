#!/usr/bin/env python3
"""Drive the three-emulator SafeMesh demo while record-mesh-demo.py captures it.

Windows + Python 3. Every step waits for the narration line that describes it
(voice/durations.json from narrate.py), so the recording needs no time-stretching
apart from the issuer's typing. Writes, next to --out:
  <out>.mp4             raw synchronized capture of A, B and C (record-mesh-demo.py)
  <out>.events.json     step times in seconds from the first captured frame
  stills/a.png b.png c.png  full-resolution screenshots for the pitch deck

Prerequisites: the app on three API 24 emulators, the emulator hub (8765) with
reverse ports, the exercise authority (8768) reachable from A, and
.cache/demo-authority/session-token.txt. The activation code is typed into the
masked field and never printed or saved. App data on all three is cleared first.

  python scripts/demo-video/drive.py --pids <A> <B> <C> --out .cache/demo-video/raw
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BUNDLE = 'org.safemesh.alerts'
KEYBOARD_IDS = ('KeyHideKbd', 'hideButton', 'KeyboardCanvas', 'CanvasKeyboard', 'inputMethodPanel', 'KeyCanvasKeyboard')
TITLE = 'Exercise: power cut in central Kraków'
BODY = ('EXERCISE ONLY. Power and the mobile network are down in central Kraków. '
        'Go to the nearest protective point on the offline map and stay with your group.')


class Phone:
    def __init__(self, hdc, serial, name, workdir, log):
        self.hdc_path, self.serial, self.name, self.workdir, self.log = hdc, serial, name, workdir, log

    def hdc(self, *args, timeout=30):
        return subprocess.run([self.hdc_path, '-t', self.serial, *args], capture_output=True, text=True,
                              encoding='utf-8', errors='replace', timeout=timeout).stdout

    def shell(self, command):
        return self.hdc('shell', command)

    def nodes(self):
        remote = f'/data/local/tmp/demo-{self.name}.json'
        local = self.workdir / f'layout-{self.name}.json'
        self.shell(f'uitest dumpLayout -p {remote}')
        local.unlink(missing_ok=True)
        self.hdc('file', 'recv', remote, str(local))
        found = {}

        def walk(node, scroll=None):
            attributes = node.get('attributes', {})
            bounds = attributes.get('origBounds') or attributes.get('bounds')
            if attributes.get('type') in ('Scroll', 'List') and attributes.get('bounds'):
                scroll = [int(v) for v in attributes['bounds'].replace('][', ',').strip('[]').split(',')]
            identifier = attributes.get('id')
            if identifier and identifier not in found and bounds:
                left, top, right, bottom = [int(v) for v in bounds.replace('][', ',').strip('[]').split(',')]
                found[identifier] = {'x': (left + right) // 2, 'y': (top + bottom) // 2, 'top': top, 'bottom': bottom,
                                     'text': attributes.get('text', ''), 'scroll': scroll}
            for child in node.get('children', []):
                walk(child, scroll)
        walk(json.loads(local.read_text(encoding='utf-8')))
        return found

    def find(self, identifier, prefix=False, attempts=6):
        for attempt in range(attempts):
            nodes = self.nodes()
            for key, node in nodes.items():
                if key == identifier or (prefix and key.startswith(identifier)):
                    scroll = node['scroll']
                    if scroll is None or (node['top'] >= scroll[1] and node['bottom'] <= scroll[3]):
                        return key, node
                    middle = (scroll[1] + scroll[3]) // 2
                    distance = max(-900, min(900, node['y'] - middle))
                    self.shell(f'uitest uiInput drag 40 {middle + distance // 2} 40 {middle - distance // 2} 800')
                    time.sleep(1.0)
                    break
            else:
                # Far off-screen nodes are missing from the dump: scroll the page down (later: up) to reveal them.
                scroll = next((n['scroll'] for n in nodes.values() if n['scroll']), None)
                if scroll is None:
                    time.sleep(0.5)
                    continue
                middle, step = (scroll[1] + scroll[3]) // 2, 450 if attempt < 3 else -450
                self.shell(f'uitest uiInput drag 40 {middle + step} 40 {middle - step} 800')
                time.sleep(1.0)
        raise RuntimeError(f'{self.name}: {identifier} not found')

    def tap(self, identifier, pause=0.6, prefix=False):
        key, node = self.find(identifier, prefix)
        self.shell(f'uitest uiInput click {node["x"]} {node["y"]}')
        self.log(f'{self.name} tap {key}')
        time.sleep(pause)

    def type_into(self, identifier, text, secret=False):
        assert "'" not in text
        _, node = self.find(identifier)
        self.shell(f'uitest uiInput click {node["x"]} {node["y"]}')
        time.sleep(0.4)
        self.shell('uitest uiInput keyEvent 2072 2017')
        self.shell('uitest uiInput keyEvent 2055')
        self.shell(f"uitest uiInput inputText {node['x']} {node['y']} '{text}'")
        self.log(f'{self.name} type {identifier} ' + ('<masked>' if secret else repr(text)))
        time.sleep(0.6)
        self.hide_keyboard()

    def hide_keyboard(self):
        """Close the on-screen keyboard: its hide key if shown, otherwise Back (only while it is open)."""
        for _ in range(3):
            nodes = self.nodes()
            if not any(name in nodes for name in KEYBOARD_IDS):
                return
            key = nodes.get('KeyHideKbd') or nodes.get('hideButton')
            if key is not None:
                self.shell(f'uitest uiInput click {key["x"]} {key["y"]}')
            else:
                self.shell('uitest uiInput keyEvent Back')
            time.sleep(0.6)

    def wait_for(self, identifier, timeout=30, prefix=False):
        deadline = time.time() + timeout
        while time.time() < deadline:
            for key in self.nodes():
                if key == identifier or (prefix and key.startswith(identifier)):
                    return
            time.sleep(0.4)
        raise RuntimeError(f'{self.name}: timed out waiting for {identifier}')

    def wait_text(self, identifier, fragment, timeout=20):
        deadline = time.time() + timeout
        while time.time() < deadline:
            node = self.nodes().get(identifier)
            if node is not None and fragment.lower() in node['text'].lower():
                return node['text']
            time.sleep(0.4)
        raise RuntimeError(f'{self.name}: {identifier} never showed {fragment!r}')

    def still(self, path):
        self.shell('uitest screenCap -p /data/local/tmp/demo-still.png')
        path.parent.mkdir(parents=True, exist_ok=True)
        self.hdc('file', 'recv', '/data/local/tmp/demo-still.png', str(path))

    def to_tabs(self):
        for _ in range(4):
            if 'tab0' in self.nodes():
                return
            self.tap('backSettings', pause=0.8)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    studio = Path(os.environ.get('DEVECO_CLI_STUDIO_PATH', str(Path.home() / 'DevEcoStudio')))
    parser.add_argument('--hdc', default=str(studio / 'sdk' / 'default' / 'openharmony' / 'toolchains' / 'hdc.exe'))
    parser.add_argument('--devices', nargs=3, default=['127.0.0.1:5555', '127.0.0.1:5557', '127.0.0.1:5559'])
    parser.add_argument('--pids', nargs=3, required=True, help='Emulator.exe process IDs of A, B and C.')
    parser.add_argument('--out', type=Path, default=ROOT / '.cache' / 'demo-video' / 'raw')
    parser.add_argument('--fps', type=int, default=15)
    parser.add_argument('--voice', type=Path, default=ROOT / '.cache' / 'demo-video' / 'voice' / 'durations.json')
    args = parser.parse_args()

    out = args.out.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    video = out.with_suffix('.mp4')
    for path in (video, video.with_suffix('.capture.json'), out.with_name(out.name + '.partial.mp4'),
                 out.with_suffix('.stop')):
        path.unlink(missing_ok=True)
    stills = out.parent / 'stills'
    log_file = out.with_suffix('.log')
    log_file.write_text('', encoding='utf-8')
    voice = json.loads(args.voice.read_text(encoding='utf-8'))
    lock = threading.Lock()
    clock = {'t0': 0.0}
    events = {}

    def log(message):
        line = f'{time.time() - clock["t0"] if clock["t0"] else 0:7.2f}s {message}'
        with lock:
            print(line, flush=True)
            with open(log_file, 'a', encoding='utf-8') as handle:
                handle.write(line + '\n')

    def mark(name):
        events[name] = round(time.time() - clock['t0'], 3)
        log(f'EVENT {name}')
        return events[name]

    def until(moment):
        delay = clock['t0'] + moment - time.time()
        if delay > 0:
            time.sleep(delay)

    def hub(*command):
        result = subprocess.run(['node', str(ROOT / 'scripts' / 'mesh-lab-control.mjs'), *command],
                                capture_output=True, text=True, cwd=ROOT, timeout=20)
        if result.returncode != 0:
            raise RuntimeError('hub: ' + result.stderr.strip())
        log('hub ' + ' '.join(command))

    def parallel(*jobs):
        errors = []

        def run(job):
            try:
                job()
            except Exception as error:  # surfaced after join
                errors.append(error)
        threads = [threading.Thread(target=run, args=(job,)) for job in jobs]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        if errors:
            raise errors[0]

    a, b, c = [Phone(args.hdc, serial, name, out.parent, log) for serial, name in zip(args.devices, 'ABC')]
    token_file = ROOT / '.cache' / 'demo-authority' / 'session-token.txt'
    token = token_file.read_text(encoding='utf-8').strip()

    # Fresh apps, fresh hub sessions, A-B in range only.
    for phone in (a, b, c):
        phone.shell('power-shell wakeup')
        phone.shell('power-shell timeout -o 3600000')
        phone.shell(f'aa force-stop {BUNDLE}')
        phone.shell(f'bm clean -n {BUNDLE} -d')
    for role in 'ABC':
        subprocess.run(['node', str(ROOT / 'scripts' / 'mesh-lab-control.mjs'), 'disconnect', role],
                       capture_output=True, text=True, cwd=ROOT, timeout=20)
    hub('reset')
    hub('links', 'AB')
    subprocess.run(['node', str(ROOT / 'scripts' / 'mesh-lab-fixtures.mjs')], cwd=ROOT, check=True, capture_output=True)
    for phone in (a, b, c):
        phone.shell(f'aa start -b {BUNDLE} -a EntryAbility')
    time.sleep(6)

    recorder = subprocess.Popen([sys.executable, str(ROOT / 'scripts' / 'record-mesh-demo.py'), '--pids', *args.pids,
                                 '--fps', str(args.fps), '--duration', '400', '--output', str(video),
                                 '--stop-file', str(out.with_suffix('.stop'))],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, cwd=ROOT)
    for line in recorder.stdout:
        if line.startswith('RECORDING_START'):
            clock['t0'] = float(line.split('epoch=')[1].split()[0])
            break
    else:
        raise RuntimeError('recorder did not start')

    try:
        mark('start')                                   # N05: the setup
        until(voice['N05'] + 0.9)

        def connect(phone):
            phone.tap('tab2')
            phone.tap('labNode' + phone.name)
            phone.tap('labStart', pause=1.0)
            phone.wait_for('labStop', timeout=20)
        connected = mark('connect')                    # N06: everyone joins
        parallel(lambda: connect(a), lambda: connect(b), lambda: connect(c))
        until(connected + voice['N06'] + 0.7)

        mark('issuer')                                  # N07: the issuer writes (sped up in the edit)

        def issuer():
            a.tap('openDiagnostics', pause=0.8)
            a.tap('openAuthority', pause=0.8)
            a.type_into('authorityToken', token, secret=True)
            a.tap('authorityLogin', pause=1.2)
            a.wait_for('authorityLogout', timeout=15)
            a.tap('draftLanguageEn')
            a.type_into('draftTitle', TITLE)
            a.type_into('draftBody', BODY)
            a.tap('severityCritical')
        parallel(issuer, lambda: b.tap('tab0'), lambda: c.tap('tab0'))
        mark('publish')
        a.tap('publishAlert', pause=0.2)
        b.wait_for('readIncoming', timeout=30)
        arrived = mark('b_banner')                      # N08: B verifies, ACKs, shows a banner
        time.sleep(2.6)
        b.tap('readIncoming', pause=1.2)
        mark('b_detail')
        a.still(stills / 'a.png')
        b.still(stills / 'b.png')
        until(arrived + voice['N08'] + 0.6)

        moving = mark('move')                           # N09: A leaves, B meets C
        time.sleep(max(0.5, voice['N09'] - 0.9))
        hub('links', 'BC')
        mark('links_bc')
        c.wait_for('readIncoming', timeout=30)
        mark('c_banner')
        until(moving + voice['N09'] + 0.3)
        hop2 = mark('c_narration')                      # N10: hop 2
        time.sleep(2.2)
        c.tap('readIncoming', pause=1.2)
        c.find('messageRoute')
        mark('c_route')
        time.sleep(0.4)
        c.still(stills / 'c.png')
        until(hop2 + voice['N10'] + 0.7)

        c.to_tabs()
        c.tap('tab2', pause=0.8)
        c.find('labPacketStatus')
        forged = mark('forge')                          # N11: a forged copy
        time.sleep(2.0)
        hub('inject', 'B', 'C', str(ROOT / '.cache' / 'mesh-lab' / 'fixtures' / 'tampered.json'))
        mark('inject')
        status = c.wait_text('labPacketStatus', 'reject')
        mark('rejected')
        log(f'C status {status!r}')
        until(forged + voice['N11'] + 0.7)

        mapping = mark('map')                           # N12: offline map
        b.to_tabs()
        b.tap('tab1', pause=1.0)
        b.type_into('searchPoints', 'florianska')
        mark('search')
        time.sleep(1.6)
        b.tap('point_', prefix=True, pause=1.0)
        mark('point')
        until(mapping + voice['N12'] + 0.6)

        nearlink = mark('nearlink')                     # N13: NearLink capability
        a.tap('backSettings', pause=0.8)
        a.tap('checkNearLink', pause=0.5)
        a.find('nearlinkStatus')
        mark('nearlink_result')
        until(nearlink + voice['N13'] + 1.4)
        mark('end')
    finally:
        out.with_suffix('.stop').write_text('stop', encoding='utf-8')
        rest = recorder.communicate(timeout=120)[0]
        log(rest.strip())
        out.with_suffix('.events.json').write_text(json.dumps(events, indent=2), encoding='utf-8')
        out.with_suffix('.stop').unlink(missing_ok=True)


if __name__ == '__main__':
    main()
