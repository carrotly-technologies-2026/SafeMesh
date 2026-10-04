#!/usr/bin/env python3
"""Capture every SafeMesh screen on one emulator as full-page PNGs and write docs/gallery.

Windows or Linux + Python 3 + Pillow. The script drives the installed app with
`uitest uiInput` through all screens, in English and Polish, light and dark. Long
pages are captured as several viewport shots and joined using the scroll offset
that `uitest dumpLayout` reports for the page content (`origBounds`), so the
joins are exact rather than guessed from pixels.

Prerequisites (the three-emulator launcher sets them up):
  * the app is installed on --device;
  * the emulator test hub listens on 127.0.0.1:8765 with a reverse port for the
    device, and the exercise authority on 127.0.0.1:8768 (needed for the issuer
    screens; skipped with a note when .cache/demo-authority/session-token.txt
    is missing).

The activation code is typed into the masked field and never printed, logged
or saved. Each variant starts from cleared app data, so it also captures the
first-launch state. The script publishes one exercise alert per variant to
connected peers.

  python scripts/capture-gallery.py --device 127.0.0.1:5555 --peer 127.0.0.1:5557:B --peer 127.0.0.1:5559:C

Peers are cleared and connected as neighbours before each variant, so the relay
screens show a live link and no older alert is synced into the shots.
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = 'org.safemesh.alerts'
VARIANTS = ['en-light', 'en-dark', 'pl-light', 'pl-dark']
DRAFTS = {
    'en': ('Exercise: power cut in central Kraków',
           'EXERCISE ONLY. Power and the mobile network are down in central Kraków. Go to the nearest '
           'protective point on the offline map and stay with your group.',
           'Kraków, Old Town'),
    'pl': ('Ćwiczenie: brak prądu w centrum Krakowa',
           'TYLKO ĆWICZENIE. W centrum Krakowa nie ma prądu ani sieci komórkowej. Udaj się do najbliższego '
           'punktu ochronnego z mapy offline i pozostań z grupą.',
           'Kraków, Stare Miasto'),
}
# (file name, English title, what it shows) in capture order.
SCREENS = [
    ('01-home-first-launch', 'Home, first launch', 'Empty inbox with the next steps: connect devices or open the map.'),
    ('02-map', 'Map', 'Bundled vector map of central Kraków with 40 State Fire Service protective points and the nearest ones.'),
    ('03-map-list', 'Map, list mode', 'All protective points sorted by straight-line distance from the labelled origin.'),
    ('04-map-search', 'Map, search', 'Address search; works with or without Polish diacritics.'),
    ('05-point-detail', 'Protective point, saved', 'Point details with access category and source; saved as the user\'s place.'),
    ('06-relay', 'Relay', 'Choose the emulator node and connect to the labelled local test link that stands in for NearLink.'),
    ('07-relay-connected', 'Relay, connected', 'Connected as node A: neighbours, delivery counters and automatic relaying.'),
    ('08-guide', 'Guide', 'Offline preparedness guide.'),
    ('09-guide-expanded', 'Guide, section open', 'A guide section expanded.'),
    ('10-settings', 'Settings', 'Appearance, language (System / Polski / English), relay comfort switches, diagnostics and version.'),
    ('11-diagnostics', 'Tests and diagnostics', 'Exercise tools, the six-check verification test and the NearLink capability check.'),
    ('12-diagnostics-results', 'Diagnostics, results', 'Exercise loaded, six checks run, and the emulator\'s NearLink result (no radio).'),
    ('13-authority-signed-out', 'Exercise authority, signed out', 'The issuer console needs an activation code; device role A grants nothing.'),
    ('14-authority-compose', 'Exercise authority, draft', 'Signed-in issuer writes a title, instructions and area, and picks language, priority and validity.'),
    ('15-authority-published', 'Exercise authority, published', 'The returned signature was verified on the device, then the alert was queued for neighbours.'),
    ('16-home-inbox', 'Home, inbox', 'New-alert banner, unread inbox of verified alerts, saved place and connection status.'),
    ('17-message-detail', 'Alert detail', 'Full signed text, issuer, area, validity and the local relay receipt (previous device, hops).'),
]
KEYBOARD_IDS = ('KeyHideKbd', 'hideButton', 'KeyboardCanvas', 'CanvasKeyboard', 'inputMethodPanel', 'KeyCanvasKeyboard')
VARIANT_TITLES = {'en-light': 'English · light', 'en-dark': 'English · dark',
                  'pl-light': 'Polski · light', 'pl-dark': 'Polski · dark'}


class Device:
    def __init__(self, hdc, serial, workdir):
        self.hdc_path, self.serial, self.workdir = hdc, serial, workdir

    def hdc(self, *args, timeout=30):
        return subprocess.run([self.hdc_path, '-t', self.serial, *args], capture_output=True, text=True,
                              encoding='utf-8', errors='replace', timeout=timeout).stdout

    def shell(self, command):
        return self.hdc('shell', command)

    def layout(self):
        self.shell('uitest dumpLayout -p /data/local/tmp/gallery-layout.json')
        local = self.workdir / 'layout.json'
        local.unlink(missing_ok=True)
        self.hdc('file', 'recv', '/data/local/tmp/gallery-layout.json', str(local))
        return Layout(json.loads(local.read_text(encoding='utf-8')))

    def screenshot(self):
        self.shell('uitest screenCap -p /data/local/tmp/gallery-shot.png')
        local = self.workdir / 'shot.png'
        local.unlink(missing_ok=True)
        self.hdc('file', 'recv', '/data/local/tmp/gallery-shot.png', str(local))
        with Image.open(local) as image:
            return image.convert('RGB')

    def click(self, x, y):
        self.shell(f'uitest uiInput click {x} {y}')

    def drag(self, x, y1, y2):
        self.shell(f'uitest uiInput drag {x} {y1} {x} {y2} 800')


def parse_bounds(value):
    left, top, right, bottom = [int(v) for v in value.replace('][', ',').strip('[]').split(',')]
    return left, top, right, bottom


class Layout:
    def __init__(self, data):
        self.nodes = []
        self.scrolls = []

        def walk(node, parent=None):
            attributes = node.get('attributes', {})
            entry = {'id': attributes.get('id', ''), 'type': attributes.get('type', ''),
                     'text': attributes.get('text', ''), 'children': node.get('children', [])}
            if attributes.get('bounds'):
                entry['bounds'] = parse_bounds(attributes['bounds'])
                entry['orig'] = parse_bounds(attributes.get('origBounds') or attributes['bounds'])
                self.nodes.append(entry)
                if entry['type'] in ('Scroll', 'List') and entry['children']:
                    child = entry['children'][0].get('attributes', {})
                    if child.get('origBounds'):
                        self.scrolls.append((entry, parse_bounds(child['origBounds'])))
            for item in node.get('children', []):
                walk(item, entry)
        walk(data)

    def page(self):
        """The main page scroll: (viewport top, viewport bottom, content top, content bottom)."""
        if not self.scrolls:
            return None
        scroll, content = max(self.scrolls, key=lambda pair: (pair[0]['bounds'][2] - pair[0]['bounds'][0]) *
                              (pair[0]['bounds'][3] - pair[0]['bounds'][1]))
        return scroll['bounds'][1], scroll['bounds'][3], content[1], content[3]

    def find(self, identifier, prefix=False):
        for node in self.nodes:
            if node['id'] == identifier or (prefix and node['id'].startswith(identifier)):
                return node
        return None


class Gallery:
    def __init__(self, device, raw_dir, out_dir, width, log):
        self.device, self.raw_dir, self.out_dir, self.width, self.log_file = device, raw_dir, out_dir, width, log
        self.started = time.time()

    def log(self, message):
        line = f'{time.time() - self.started:7.1f}s {message}'
        print(line, flush=True)
        with open(self.log_file, 'a', encoding='utf-8') as handle:
            handle.write(line + '\n')

    # ---- navigation -------------------------------------------------------
    def bring_into_view(self, identifier, prefix=False, attempts=8):
        for _ in range(attempts):
            layout = self.device.layout()
            node = layout.find(identifier, prefix)
            page = layout.page()
            if node is None:
                if page is None:
                    break
                self.scroll_by(layout, 900)
                continue
            top, bottom = node['orig'][1], node['orig'][3]
            if page is None:
                return node
            view_top, view_bottom = page[0], page[1]
            inside_page = self.inside(layout, node)
            if not inside_page or (top >= view_top and bottom <= view_bottom):
                return node
            centre = (top + bottom) // 2
            self.scroll_by(layout, centre - (view_top + view_bottom) // 2)
        raise RuntimeError(f'{identifier} not found on screen')

    @staticmethod
    def inside(layout, node):
        page = layout.page()
        left, top, right, bottom = node['orig']
        for scroll, content in layout.scrolls:
            if content[1] <= top and bottom <= content[3] and scroll['bounds'][1] == page[0]:
                return True
        return False

    def scroll_by(self, layout, distance):
        """Scroll the page content up by `distance` pixels (negative scrolls down), no fling."""
        page = layout.page()
        if page is None or distance == 0:
            return
        view_top, view_bottom = page[0], page[1]
        span = int((view_bottom - view_top) * 0.8)
        distance = max(-span, min(span, distance))
        middle = (view_top + view_bottom) // 2
        start, end = middle + distance // 2, middle - distance // 2
        self.device.drag(40, start, end)
        time.sleep(2.0)  # let the scroll bar fade out

    def to_top(self):
        for _ in range(8):
            layout = self.device.layout()
            page = layout.page()
            if page is None or page[2] >= page[0]:
                return
            self.scroll_by(layout, -(page[0] - page[2]))

    def tap(self, identifier, pause=0.8, prefix=False):
        node = self.bring_into_view(identifier, prefix)
        left, top, right, bottom = node['orig']
        self.device.click((left + right) // 2, (top + bottom) // 2)
        self.log(f'tap {node["id"]}')
        time.sleep(pause)

    def type_into(self, identifier, text, secret=False):
        """Replace the field's text (inputText appends, and some fields have a default)."""
        assert "'" not in text
        node = self.bring_into_view(identifier)
        left, top, right, bottom = node['orig']
        x, y = (left + right) // 2, (top + bottom) // 2
        self.device.click(x, y)
        time.sleep(0.5)
        self.device.shell('uitest uiInput keyEvent 2072 2017')  # Ctrl+A
        self.device.shell('uitest uiInput keyEvent 2055')  # Delete
        self.device.shell(f"uitest uiInput inputText {x} {y} '{text}'")
        self.log(f'type {identifier} ' + ('<masked>' if secret else repr(text)))
        time.sleep(0.8)
        self.hide_keyboard()

    def hide_keyboard(self):
        """Close the on-screen keyboard: its hide key if shown, otherwise Back (only while it is open)."""
        for _ in range(3):
            layout = self.device.layout()
            if not any(layout.find(name) for name in KEYBOARD_IDS):
                return
            # The normal keyboard has KeyHideKbd (not while it shows suggestions); the secure one hideButton.
            key = layout.find('KeyHideKbd') or layout.find('hideButton')
            if key is not None:
                left, top, right, bottom = key['orig']
                self.device.click((left + right) // 2, (top + bottom) // 2)
            else:
                self.device.shell('uitest uiInput keyEvent Back')
            time.sleep(0.7)

    def wait_for(self, identifier, timeout=25, prefix=False):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.device.layout().find(identifier, prefix) is not None:
                return
            time.sleep(0.5)
        raise RuntimeError(f'timed out waiting for {identifier}')

    def connect_lab(self, role):
        """Connect to the emulator hub as `role`, dropping a stale session of a cleared app first."""
        self.tap('tab2')
        self.tap('labNode' + role)
        for attempt in range(3):
            self.tap('labStart', pause=2.0)
            try:
                self.wait_for('labStop', timeout=12)
                return
            except RuntimeError:
                self.log(f'{role} not connected (attempt {attempt + 1}); dropping a stale hub session')
                subprocess.run(['node', str(ROOT / 'scripts' / 'mesh-lab-control.mjs'), 'disconnect', role],
                               capture_output=True, text=True, timeout=20)
                time.sleep(2.0)
        raise RuntimeError(f'could not connect {role} to the emulator hub')

    def to_tabs(self):
        for _ in range(4):
            if self.device.layout().find('tab0') is not None:
                return
            self.tap('backSettings')
        raise RuntimeError('could not return to the tab screens')

    # ---- capture ----------------------------------------------------------
    def capture(self, variant, name):
        """Capture the current screen; long pages become one full-page image."""
        time.sleep(0.8)
        self.hide_keyboard()
        self.to_top()
        layout = self.device.layout()
        page = layout.page()
        first = self.device.screenshot()
        shots = [(first, page[2] if page else 0)]
        if page is not None:
            view_top, view_bottom, content_top, content_bottom = page
            height = content_bottom - content_top
            while shots[-1][1] + height > view_bottom + 1:
                self.scroll_by(layout, int((view_bottom - view_top) * 0.7))
                layout = self.device.layout()
                current = layout.page()
                if current is None or current[2] == shots[-1][1]:
                    break
                shots.append((self.device.screenshot(), current[2]))
        if len(shots) == 1:
            image = first
        else:
            view_top, view_bottom = page[0], page[1]
            start = shots[0][1]
            scrolled = start - shots[-1][1]
            width, screen_height = first.size
            image = Image.new('RGB', (width, screen_height + scrolled))
            image.paste(first.crop((0, 0, width, view_bottom)), (0, 0))
            for shot, content_top in shots[1:]:
                offset = start - content_top
                image.paste(shot.crop((0, view_top, width, view_bottom)), (0, view_top + offset))
            image.paste(shots[-1][0].crop((0, view_bottom, width, screen_height)), (0, view_bottom + scrolled))
            self.to_top()
        raw = self.raw_dir / variant / f'{name}.png'
        raw.parent.mkdir(parents=True, exist_ok=True)
        image.save(raw, optimize=True)
        small = image.resize((self.width, round(image.height * self.width / image.width)), Image.LANCZOS)
        out = self.out_dir / variant / f'{name}.png'
        out.parent.mkdir(parents=True, exist_ok=True)
        small.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(out, optimize=True)
        self.log(f'captured {variant}/{name} ({len(shots)} shot(s), {image.height}px tall)')

    # ---- scenario ---------------------------------------------------------
    def as_device(self, device, action):
        own = self.device
        self.device = device
        try:
            return action()
        finally:
            self.device = own

    @staticmethod
    def clear_app(device):
        device.shell('power-shell wakeup')
        device.shell('power-shell timeout -o 3600000')
        device.shell(f'aa force-stop {BUNDLE}')
        device.shell(f'bm clean -n {BUNDLE} -d')

    def run_variant(self, variant, token, peers=()):
        language, theme = variant.split('-')
        # Clear every app before any of them connects, so no alert from an earlier run can sync in.
        # Default lab topology: A-B and B-C in range (the demo recording may have left B-C only).
        for device in [self.device] + [peer for peer, _ in peers]:
            self.clear_app(device)
        for role in 'ABC':
            subprocess.run(['node', str(ROOT / 'scripts' / 'mesh-lab-control.mjs'), 'disconnect', role],
                           capture_output=True, text=True, timeout=20)
        subprocess.run(['node', str(ROOT / 'scripts' / 'mesh-lab-control.mjs'), 'links', 'AB', 'BC'],
                       capture_output=True, text=True, timeout=20)
        for peer, role in peers:
            peer.shell(f'aa start -b {BUNDLE} -a EntryAbility')
        time.sleep(4)
        for peer, role in peers:
            self.as_device(peer, lambda: (self.wait_for('tab0'), self.connect_lab(role)))
            self.log(f'peer {role} cleared and connected')

        self.device.shell(f'aa start -b {BUNDLE} -a EntryAbility')
        time.sleep(4)
        self.wait_for('tab0')
        self.tap('openSettings')
        self.tap('language' + ('En' if language == 'en' else 'Pl'))
        self.tap('theme' + ('Light' if theme == 'light' else 'Dark'))
        self.to_tabs()
        self.capture(variant, '01-home-first-launch')

        self.tap('tab1', pause=1.2)
        self.capture(variant, '02-map')
        self.tap('mapModelist')
        self.capture(variant, '03-map-list')
        self.type_into('searchPoints', 'Bracka')
        self.capture(variant, '04-map-search')
        self.tap('point_', prefix=True, pause=1.2)
        self.tap('savePoint', pause=1.5)
        self.capture(variant, '05-point-detail')
        self.to_tabs()

        self.tap('tab2')
        self.capture(variant, '06-relay')
        self.connect_lab('A')
        time.sleep(2.0)
        self.capture(variant, '07-relay-connected')

        self.tap('tab3')
        self.capture(variant, '08-guide')
        self.tap('guideItem2')
        self.capture(variant, '09-guide-expanded')

        self.tap('openSettings')
        self.capture(variant, '10-settings')
        self.tap('settingsDiagnostics')
        self.capture(variant, '11-diagnostics')

        # Publish while A is still linked to B (the NearLink check below switches the transport).
        self.tap('openAuthority')
        self.capture(variant, '13-authority-signed-out')
        if token:
            title, body, area = DRAFTS[language]
            self.type_into('authorityToken', token, secret=True)
            self.tap('authorityLogin', pause=1.5)
            self.wait_for('authorityLogout', timeout=15)
            self.tap('draftLanguage' + ('En' if language == 'en' else 'Pl'))
            self.type_into('draftTitle', title)
            self.type_into('draftBody', body)
            self.type_into('draftArea', area)
            self.tap('severityCritical')
            self.capture(variant, '14-authority-compose')
            self.tap('publishAlert', pause=3.0)
            self.capture(variant, '15-authority-published')
            self.tap('authorityLogout', pause=1.0)
        else:
            self.log('no activation code: issuer draft and publication screens skipped')
        self.tap('backSettings', pause=1.0)

        self.tap('diagnosticDrill', pause=2.5)
        self.tap('runRelay', pause=7.0)
        self.tap('checkNearLink', pause=3.0)
        self.capture(variant, '12-diagnostics-results')

        # Back on the emulator link for the inbox and the alert detail.
        self.to_tabs()
        self.connect_lab('A')
        time.sleep(2.0)
        self.tap('tab0', pause=1.0)
        self.capture(variant, '16-home-inbox')
        self.tap('message_', prefix=True, pause=1.2)
        self.capture(variant, '17-message-detail')
        self.to_tabs()
        self.tap('tab2')
        if self.device.layout().find('labStop') is not None:
            self.tap('labStop', pause=1.0)

def write_index(out_dir, variants):
    lines = [
        '# SafeMesh screen gallery',
        '',
        'Every screen of SafeMesh v1.6.0 as it runs on a HarmonyOS API 24 phone emulator, in English and Polish, '
        'light and dark. Long screens are shown as one full-page image: `scripts/capture-gallery.py` drives the app '
        'with `uitest`, scrolls each page and joins the shots at the scroll offset reported by the layout dump.',
        '',
        'Each variant starts from cleared app data. The relay screens are connected to the labelled local emulator '
        'test link (the stand-in for NearLink), and the issuer screens use the local exercise authority. The '
        'activation code was typed into a masked field and appears nowhere. Click an image for the full size.',
        '',
        'Regenerate with `python scripts/capture-gallery.py --device 127.0.0.1:5555 --peer 127.0.0.1:5557:B '
        '--peer 127.0.0.1:5559:C` (see the script header for prerequisites).',
        '',
        '| Screen | ' + ' | '.join(VARIANT_TITLES[v] for v in variants) + ' |',
        '| --- | ' + ' | '.join('---' for _ in variants) + ' |',
    ]
    for name, title, text in SCREENS:
        cells = []
        for variant in variants:
            path = out_dir / variant / f'{name}.png'
            cells.append(f'<a href="{variant}/{name}.png"><img src="{variant}/{name}.png" width="160" '
                         f'alt="{title}, {VARIANT_TITLES[variant]}"></a>' if path.exists() else '—')
        lines.append(f'| **{title}**<br>{text} | ' + ' | '.join(cells) + ' |')
    lines.append('')
    (out_dir / 'README.md').write_text('\n'.join(lines), encoding='utf-8', newline='\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    studio = Path(os.environ.get('DEVECO_CLI_STUDIO_PATH', str(Path.home() / 'DevEcoStudio')))
    default_hdc = studio / 'sdk' / 'default' / 'openharmony' / 'toolchains' / ('hdc.exe' if os.name == 'nt' else 'hdc')
    parser.add_argument('--hdc', default=os.environ.get('HDC', str(default_hdc)))
    parser.add_argument('--device', default='127.0.0.1:5555', help='Emulator A (has the issuer reverse port).')
    parser.add_argument('--variants', default=','.join(VARIANTS))
    parser.add_argument('--peer', action='append', default=[], metavar='SERIAL:ROLE',
                        help='Neighbour emulator to clear and connect before each variant, e.g. 127.0.0.1:5557:B.')
    parser.add_argument('--out', type=Path, default=ROOT / 'docs' / 'gallery')
    parser.add_argument('--raw', type=Path, default=ROOT / '.cache' / 'gallery-raw',
                        help='Full-resolution copies (git-ignored).')
    parser.add_argument('--width', type=int, default=660, help='Width of the committed images.')
    parser.add_argument('--index-only', action='store_true', help='Only rewrite docs/gallery/README.md.')
    args = parser.parse_args()
    variants = [v for v in args.variants.split(',') if v]
    if any(v not in VARIANTS for v in variants):
        parser.error('variants must be among ' + ', '.join(VARIANTS))
    args.out.mkdir(parents=True, exist_ok=True)
    if not args.index_only:
        args.raw.mkdir(parents=True, exist_ok=True)
        token_file = ROOT / '.cache' / 'demo-authority' / 'session-token.txt'
        token = token_file.read_text(encoding='utf-8').strip() if token_file.exists() else ''
        gallery = Gallery(Device(args.hdc, args.device, args.raw), args.raw, args.out, args.width,
                          args.raw / 'capture.log')
        peers = [(Device(args.hdc, spec.rsplit(':', 1)[0], args.raw), spec.rsplit(':', 1)[1]) for spec in args.peer]
        for variant in variants:
            gallery.log(f'--- {variant}')
            gallery.run_variant(variant, token, peers)
    write_index(args.out, [v for v in VARIANTS if (args.out / v).exists()])
    print('Gallery written to', args.out)


if __name__ == '__main__':
    sys.exit(main())
