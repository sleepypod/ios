#!/usr/bin/env python3
"""Capture sleepypod's simulator UI and render store images and preview videos.

No desktop clicks are needed. Debug-only launch arguments put the app in demo
mode on a chosen tab and control; `-marketingCapture YES` skips the
notification prompt and the DEMO badge. Videos come from the paced XCUITests
in SleepypodUITests/MarketingTour.swift, recorded with simctl and trimmed to
the marks each test prints. Release builds ignore the marketingCapture and uiRoute hooks.
"""
from __future__ import annotations
import argparse
import json
import os
import plistlib
from pathlib import Path
import re
import signal
import subprocess
import threading
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
DERIVED = REPO / 'build' / 'marketing'
DEVICES = {'iphone-6.9': 'iPhone 17 Pro Max'}
APPEARANCES = {'dark': 'Dark', 'light': 'Light'}
# Matches the app's `background` colour so letterboxing disappears into the UI.
PAD = {'dark': '0x0B0B0C', 'light': '0xF6F6F5'}
BASE_ARGS = {'apiBackend': 'demo', 'onboardingComplete': 'YES', 'healthSyncEnabled': 'NO',
             'marketingCapture': 'YES', 'tempControl': 'dial', 'uiRoute': 'none'}
SHOTS = [
    ('01-temperature', {}),
    ('02-both-sides', {'tempControl': 'sides'}),
    ('03-night-dawn', {'tempControl': 'stepper'}),
    ('04-schedule', {'uiRoute': 'schedule'}),
    ('05-sleep-night', {'uiRoute': 'sleep'}),
    ('06-sleep-week', {'uiRoute': 'weektrend'}),
    ('07-apple-watch', {'uiRoute': 'watch'}),
    # Health onboarding needs a non-demo backend; it never connects before step 3 finishes.
    ('08-apple-health', {'uiRoute': 'onboard3', 'apiBackend': 'sleepypod-core', 'onboardingComplete': 'NO',
                         'podIPAddress': ''}),
]
# (output name, MarketingTour test, allowed seconds). App Store previews must run 15–30 s;
# the walkthrough is for the web and social, so it is longer than App Store Connect accepts.
TOURS = [
    ('clip-temperature', 'testClipTemperature', (15, 30)),
    ('clip-night-dawn', 'testClipNightAndDawn', (15, 30)),
    ('clip-schedule', 'testClipSchedule', (15, 30)),
    ('clip-sleep-watch', 'testClipSleepAndWatch', (15, 30)),
    ('walkthrough-sleepypod', 'testWalkthrough', (60, 120)),
]
PREVIEW = (886, 1920)
SOCIAL = (1080, 1920)
MARK = re.compile(r'MARKETING_MARK (begin|end) (\d+\.\d+)')


def run(*args, check=True, env=None):
    return subprocess.run([str(a) for a in args], check=check, capture_output=True, text=True, env=env)


def sim(*args, check=True):
    return run('xcrun', 'simctl', *args, check=check)


def device(name):
    # Isolate clean installs from developers' normal simulator app data.
    runtime_list = json.loads(sim('list', 'runtimes', '-j').stdout)['runtimes']
    runtimes = [r for r in runtime_list if r.get('isAvailable') and '.iOS-' in r['identifier']]
    if not runtimes:
        raise RuntimeError('No available iOS simulator runtime')
    runtime = max(runtimes, key=lambda r: tuple(map(int, r['version'].split('.'))))['identifier']
    capture_name = f'sleepypod Marketing — {name}'
    listing = json.loads(sim('list', 'devices', 'available', '-j').stdout)
    for candidate in listing['devices'].get(runtime, []):
        if candidate['name'] == capture_name and candidate.get('isAvailable'):
            return candidate
    types = json.loads(sim('list', 'devicetypes', '-j').stdout)['devicetypes']
    device_type = next((d['identifier'] for d in types if d['name'] == name), None)
    if device_type is None:
        raise RuntimeError(f'No simulator device type named {name}')
    udid = sim('create', capture_name, device_type, runtime).stdout.strip()
    return {'udid': udid, 'state': 'Shutdown'}


def launch(udid, bundle, appearance, overrides):
    sim('terminate', udid, bundle, check=False)
    args = dict(BASE_ARGS, appearance=APPEARANCES[appearance], **overrides)
    sim('launch', udid, bundle, *[part for key, value in args.items() for part in (f'-{key}', value)])


def png_size(path):
    with path.open('rb') as handle:
        header = handle.read(24)
    return int.from_bytes(header[16:20], 'big'), int.from_bytes(header[20:24], 'big')


def xctestrun():
    runs = sorted((DERIVED / 'Build' / 'Products').glob('Sleepypod_*.xctestrun'))
    if not runs:
        raise RuntimeError(f'No .xctestrun in {DERIVED}; build without --skip-build first')
    return runs[-1]


class Recorder:
    """`simctl io recordVideo`, timestamped when it reports the first frame."""

    def __init__(self, udid, path):
        path.unlink(missing_ok=True)
        self.path = path
        self.started = None
        self.log = []
        self.ready = threading.Event()
        launched = time.time()
        self.process = subprocess.Popen(['xcrun', 'simctl', 'io', udid, 'recordVideo', '--codec=h264', '--force',
                                         str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        threading.Thread(target=self._drain, daemon=True).start()
        if not self.ready.wait(15):
            self.stop()
            raise RuntimeError(f'recordVideo did not start: {"".join(self.log)}')
        self.started = self.started or launched

    def _drain(self):
        for line in self.process.stderr:
            self.log.append(line)
            if 'Recording started' in line and not self.ready.is_set():
                self.started = time.time()
                self.ready.set()
        self.ready.set()

    def stop(self):
        if self.process.poll() is None:
            self.process.send_signal(signal.SIGINT)
        try:
            self.process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        if not self.path.exists() or self.path.stat().st_size == 0:
            raise RuntimeError(f'Recording failed: {"".join(self.log)}')


def record_tour(udid, test, raw, appearance):
    env = dict(os.environ, TEST_RUNNER_MARKETING_TOUR='1', TEST_RUNNER_MARKETING_APPEARANCE=APPEARANCES[appearance])
    recorder = Recorder(udid, raw)
    try:
        result = run('xcodebuild', 'test-without-building', '-xctestrun', xctestrun(),
                     '-destination', f'id={udid}', '-parallel-testing-enabled', 'NO',
                     f'-only-testing:SleepypodUITests/MarketingTour/{test}', check=False, env=env)
    finally:
        recorder.stop()
    (raw.with_suffix('.log')).write_text(result.stdout + result.stderr)
    marks = {name: float(value) for name, value in MARK.findall(result.stdout + result.stderr)}
    if result.returncode or set(marks) != {'begin', 'end'}:
        raise RuntimeError(f'{test} failed (exit {result.returncode}, marks {marks}); see {raw.with_suffix(".log")}')
    return marks['begin'] - recorder.started, marks['end'] - recorder.started


def encode(raw, output, size, start, duration, pad, limits):
    """Trim [start, start+duration) of a variable-rate capture to constant 30 fps H.264 with silent stereo AAC."""
    width, height = size
    run('ffmpeg', '-y', '-loglevel', 'error', '-i', raw, '-f', 'lavfi', '-i',
        'anullsrc=channel_layout=stereo:sample_rate=44100', '-filter_complex',
        f'[0:v]tpad=stop_mode=clone:stop_duration=5,fps=30,'
        f'trim=start={start:.3f}:duration={duration:.3f},setpts=PTS-STARTPTS,'
        f'scale={width}:{height}:force_original_aspect_ratio=decrease:flags=lanczos,'
        f'pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color={pad},setsar=1[v]',
        '-map', '[v]', '-map', '1:a', '-t', f'{duration:.3f}',
        '-c:v', 'libx264', '-profile:v', 'high', '-pix_fmt', 'yuv420p', '-crf', '18', '-r', '30',
        '-c:a', 'aac', '-b:a', '128k', '-ac', '2', '-shortest', '-movflags', '+faststart', output)
    info = json.loads(run('ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', output).stdout)
    video = next(s for s in info['streams'] if s['codec_type'] == 'video')
    audio = next(s for s in info['streams'] if s['codec_type'] == 'audio')
    seconds = float(info['format']['duration'])
    assert (video['width'], video['height']) == size, (output, video['width'], video['height'])
    assert video['codec_name'] == 'h264' and video['r_frame_rate'] == '30/1', (output, video['r_frame_rate'])
    assert audio['codec_name'] == 'aac' and audio['channels'] == 2, output
    assert limits[0] <= seconds <= limits[1], f'{output.name} runs {seconds:.1f}s, outside {limits}'
    output.with_suffix('.json').write_text(json.dumps(info, indent=2) + '\n')
    return seconds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true', help='Reuse the last marketing build')
    parser.add_argument('--video', action='store_true', help='Also record the clips and the walkthrough')
    parser.add_argument('--device', choices=DEVICES, action='append')
    parser.add_argument('--appearance', choices=APPEARANCES, action='append',
                        help='Screenshot appearances (default: dark and light)')
    parser.add_argument('--video-appearance', choices=APPEARANCES, default='dark')
    parser.add_argument('--only', choices=[name for name, _ in SHOTS] + [name for name, _, _ in TOURS], action='append', help='Only this screenshot or tour name (repeatable)')
    parser.add_argument('--keep-booted', action='store_true')
    args = parser.parse_args()
    selected = args.device or list(DEVICES)
    looks = args.appearance or list(APPEARANCES)
    wanted = lambda name: not args.only or name in args.only
    app = DERIVED / 'Build/Products/Debug-iphonesimulator/Sleepypod.app'
    if not args.skip_build:
        print('Building sleepypod marketing capture app and UI tests…', flush=True)
        DERIVED.mkdir(parents=True, exist_ok=True)
        result = run('xcodebuild', 'build-for-testing', '-project', REPO / 'Sleepypod.xcodeproj',
                     '-scheme', 'Sleepypod', '-configuration', 'Debug',
                     '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', DERIVED, check=False)
        (DERIVED / 'build.log').write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(f'Build failed; see {DERIVED / "build.log"}')
    if not app.is_dir():
        raise RuntimeError(f'Missing build: {app}')
    with (app / 'Info.plist').open('rb') as handle:
        bundle = plistlib.load(handle)['CFBundleIdentifier']
    for family in selected:
        d = device(DEVICES[family]); udid = d['udid']; started = d['state'] != 'Booted'
        raw = HERE / 'raw' / family; output = HERE / 'output'
        try:
            if started:
                sim('boot', udid)
            sim('bootstatus', udid, '-b')
            # A clean install drops any notification prompt left pending by an earlier non-capture launch.
            sim('uninstall', udid, bundle, check=False)
            sim('install', udid, app)
            sim('status_bar', udid, 'override', '--time', '9:41', '--dataNetwork', 'wifi',
                '--wifiMode', 'active', '--wifiBars', '3', '--cellularMode', 'active',
                '--cellularBars', '4', '--batteryState', 'discharging', '--batteryLevel', '100')
            for appearance in looks:
                sim('ui', udid, 'appearance', appearance)
                (raw / appearance).mkdir(parents=True, exist_ok=True)
                for filename, overrides in SHOTS:
                    if not wanted(filename):
                        continue
                    print(f'Capturing {family} {appearance}: {filename}', flush=True)
                    launch(udid, bundle, appearance, overrides)
                    time.sleep(9)
                    path = raw / appearance / f'{filename}.png'
                    sim('io', udid, 'screenshot', '--type=png', path)
                    print(f'  {path.relative_to(HERE)} {"x".join(map(str, png_size(path)))}', flush=True)
                sim('terminate', udid, bundle, check=False)
            if args.video:
                look = args.video_appearance
                sim('ui', udid, 'appearance', look)
                (raw / 'video').mkdir(parents=True, exist_ok=True)
                for name, test, limits in TOURS:
                    if not wanted(name):
                        continue
                    print(f'Recording {family} {look}: {name} ({test})…', flush=True)
                    source = raw / 'video' / f'{name}.mp4'
                    begin, end = record_tour(udid, test, source, look)
                    start, duration = max(0, begin - 0.2), end - begin + 0.4
                    preview = output / family / f'{name}.mp4'
                    preview.parent.mkdir(parents=True, exist_ok=True)
                    seconds = encode(source, preview, PREVIEW, start, duration, PAD[look], limits)
                    print(f'  {preview.relative_to(HERE)} {PREVIEW[0]}x{PREVIEW[1]} {seconds:.1f}s', flush=True)
                    social = output / 'social' / f'{name}-{SOCIAL[0]}x{SOCIAL[1]}.mp4'
                    social.parent.mkdir(parents=True, exist_ok=True)
                    encode(source, social, SOCIAL, start, duration, PAD[look], limits)
                    print(f'  {social.relative_to(HERE)} {SOCIAL[0]}x{SOCIAL[1]} {seconds:.1f}s', flush=True)
        finally:
            sim('terminate', udid, bundle, check=False)
            sim('status_bar', udid, 'clear', check=False)
            if started and not args.keep_booted:
                sim('shutdown', udid, check=False)
        if family == 'iphone-6.9' and any(wanted(name) for name, _ in SHOTS):
            for variant, size in [('iphone-6.9', '1320x2868'), ('iphone-6.5', '1284x2778')]:
                print(f'Rendering {variant} ({", ".join(looks)})…', flush=True)
                appearance_args = [part for look in looks for part in ('--appearance', look)]
                selection_args = [part for name, _ in SHOTS if wanted(name) for part in ('--only', name)]
                result = run('uv', 'run', HERE / 'generate.py', '--manifest', HERE / f'manifest.{variant}.json',
                             '--size', size, *appearance_args, *selection_args, check=False)
                if result.returncode:
                    raise RuntimeError(f'Rendering {variant} failed:\n{result.stderr}')
    print(f'Ready for visual review: {HERE / "output"}', flush=True)


if __name__ == '__main__':
    main()
