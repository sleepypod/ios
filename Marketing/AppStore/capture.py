#!/usr/bin/env python3
"""Capture sleepypod's simulator UI and render store images and preview videos.

No desktop clicks are needed. Debug-only launch arguments put the app in demo
mode on a chosen tab and control; `-marketingCapture YES` skips the
notification prompt and the DEMO badge. Videos come from the paced XCUITests
in SleepypodUITests/MarketingTour.swift, recorded with simctl between
the flushed marks each test prints. Release builds ignore the marketingCapture and uiRoute hooks.
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
# Capture profile: simulator, the store sets rendered from its captures (manifest variant, size)
# and the app-preview size. Social cuts are only made from the iPhone tours.
DEVICES = {
    'iphone-6.9': {'simulator': 'iPhone 17 Pro Max', 'preview': (886, 1920), 'social': True,
                   'renders': [('iphone-6.9', '1320x2868'), ('iphone-6.5', '1284x2778')]},
    # 13-inch iPad slot: 2064x2752 screenshots, 1200x1600 previews (4:3).
    'ipad-13': {'simulator': 'iPad Pro 13-inch (M5)', 'preview': (1200, 1600), 'social': False,
                'renders': [('ipad-13', '2064x2752')]},
    # iPhone Duo unfolded as it's held: the inner display (LCD-1) in landscape gives 2853x2007 screenshots
    # and 1920x886 previews, plus the unfold clip, which starts on the cover display.
    'iphone-duo': {'simulator': 'iPhone Duo', 'preview': (1920, 886), 'social': False, 'display': 'LCD-1',
                   'posture': 'open', 'unfold_clip': True, 'renders': [('iphone-duo', '2853x2007')]},
    # The same Duo folded: its cover display (LCD) at Apple's 1398x2034 outer-display size. Screenshots only.
    'iphone-duo-cover': {'simulator': 'iPhone Duo', 'preview': None, 'social': False, 'display': 'LCD',
                         'posture': 'folded', 'renders': [('iphone-duo-cover', '1398x2034')]},
}
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
    ('08-apple-health', {'uiRoute': 'health'}),
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
SOCIAL = (1080, 1920)
# The unfold clip: an App Store preview for the Duo's landscape slot and a 16:9 cut with the device drawn.
UNFOLD = ('clip-unfold', 'testClipUnfold', (15, 30))
UNFOLD_SOCIAL = (1920, 1080)
MARK = re.compile(r'MARKETING_MARK (begin|end|unfold|resume) (\d+\.\d+)')


def run(*args, check=True, env=None):
    return subprocess.run([str(a) for a in args], check=check, capture_output=True, text=True, env=env)


def sim(*args, check=True):
    return run('xcrun', 'simctl', *args, check=check)


def device(name):
    # Isolate clean installs from developers' normal simulator app data.
    runtime_list = json.loads(sim('list', 'runtimes', '-j').stdout)['runtimes']
    # Newest iOS runtime that can run this device type; a beta runtime may support only a few devices.
    runtimes = [r for r in runtime_list if r.get('isAvailable') and '.iOS-' in r['identifier']
                and any(t['name'] == name for t in r.get('supportedDeviceTypes', [{'name': name}]))]
    if not runtimes:
        raise RuntimeError(f'No available iOS simulator runtime for {name}')
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


def hinge_helper():
    """Builds duo_hinge.m for the simulator SDK the first time, or after it changes."""
    source = HERE / 'duo_hinge.m'
    helper = DERIVED / 'duo_hinge'
    if not helper.exists() or helper.stat().st_mtime < source.stat().st_mtime:
        DERIVED.mkdir(parents=True, exist_ok=True)
        run('xcrun', '-sdk', 'iphonesimulator', 'clang', '-arch', 'arm64', '-mios-simulator-version-min=17.0', '-O2',
            '-o', helper, source, '-framework', 'IOKit', '-framework', 'CoreFoundation')
        run('codesign', '-f', '-s', '-', helper)
    return helper


def displays(udid):
    result = run('xcrun', 'devicectl', 'device', 'info', 'displays', '-d', udid, '-q', '-j', '-', check=False)
    if result.returncode or not result.stdout:
        return {}
    return {d.get('name'): d for d in json.loads(result.stdout).get('result', {}).get('displays', [])}


def set_posture(udid, posture):
    """Opens an iPhone Duo flat with the inner display in landscape (`open`), or closes it onto the cover
    display (`folded`), then checks with devicectl that the expected display hosts the UI.

    The device stays in portrait, as a folded phone is held, which shows the unfolded inner display in
    landscape. The simulator now and then drops a hinge event, so the event is resent until it takes.
    """
    helper = hinge_helper()
    angle, name, rotation = ('180', 'LCD-1', 'rot90') if posture == 'open' else ('0', 'LCD', 'rot0')
    sim('spawn', udid, helper, 'orient', 'portrait')
    for _ in range(5):
        sim('spawn', udid, helper, angle)
        for _ in range(12):
            target = displays(udid).get(name, {})
            if target.get('active') and target.get('currentOrientation') == rotation:
                time.sleep(1.5)  # Let the app finish moving to that display.
                return
            time.sleep(0.5)
    raise RuntimeError(f'The iPhone Duo did not reach the {posture} posture')


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

    def __init__(self, udid, path, display=None):
        path.unlink(missing_ok=True)
        self.path = path
        self.started = None
        self.log = []
        self.ready = threading.Event()
        launched = time.time()
        display_args = [f'--display={display}'] if display else []
        self.process = subprocess.Popen(['xcrun', 'simctl', 'io', udid, 'recordVideo', '--codec=h264', '--force',
                                         *display_args,
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


def record_tour(udid, test, raw, appearance, display=None):
    env = dict(os.environ, TEST_RUNNER_MARKETING_TOUR='1', TEST_RUNNER_MARKETING_APPEARANCE=APPEARANCES[appearance])
    command = ['xcodebuild', 'test-without-building', '-xctestrun', str(xctestrun()),
               '-destination', f'id={udid}', '-parallel-testing-enabled', 'NO',
               '-collect-test-diagnostics', 'never',
               f'-only-testing:SleepypodUITests/MarketingTour/{test}']
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    recorder = None
    marks = set()
    try:
        with raw.with_suffix('.log').open('w') as log:
            for line in process.stdout:
                log.write(line)
                log.flush()
                marker = MARK.search(line)
                if marker is None:
                    continue
                name, timestamp = marker.groups()
                # Tests hold the settled first/last screen for three seconds around
                # each flushed marker. Reject delayed delivery rather than exporting
                # a clip that misses actions or includes the simulator Home screen.
                if not 0 <= time.time() - float(timestamp) < 2:
                    raise RuntimeError('Capture marker delivery was delayed; recapture on an idle simulator')
                marks.add(name)
                if name == 'begin':
                    recorder = Recorder(udid, raw, display)
                    if time.time() - float(timestamp) >= 3:
                        raise RuntimeError('Recorder startup exceeded the opening hold; recapture on an idle simulator')
                elif recorder is not None:
                    recorder.stop()
                    recorder = None
            result = process.wait()
        if result or marks != {'begin', 'end'}:
            raise RuntimeError(f'{test} failed (exit {result}, marks {marks}); see {raw.with_suffix(".log")}')
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait()
        if recorder is not None:
            recorder.stop()
    seconds = float(run('ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                        '-of', 'default=noprint_wrappers=1:nokey=1', raw).stdout)
    return 0, seconds


def record_unfold(udid, raw, output, look, preview):
    """The Duo opening: the cover display until the test marks `unfold`, then the inner display from `resume`.

    simctl records one display at a time and the simulator has no 3D chrome to film, so the two recordings
    are joined by unfold.py, which draws the device opening between them.
    """
    name, test, limits = UNFOLD
    print(f'Recording iphone-duo {look}: {name} ({test})…', flush=True)
    set_posture(udid, 'folded')
    cover, inner = raw / f'{name}-cover.mp4', raw / f'{name}-inner.mp4'
    env = dict(os.environ, TEST_RUNNER_MARKETING_TOUR='1', TEST_RUNNER_MARKETING_APPEARANCE=APPEARANCES[look])
    command = ['xcodebuild', 'test-without-building', '-xctestrun', str(xctestrun()),
               '-destination', f'id={udid}', '-parallel-testing-enabled', 'NO',
               '-collect-test-diagnostics', 'never', f'-only-testing:SleepypodUITests/MarketingTour/{test}']
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    recorder, marks, inner_start, times = None, set(), 0.0, {}
    try:
        with (raw / f'{name}.log').open('w') as log:
            for line in process.stdout:
                log.write(line)
                log.flush()
                marker = MARK.search(line)
                if marker is None:
                    continue
                mark, timestamp = marker.group(1), float(marker.group(2))
                # `resume` is used by its timestamp, so only the recorder boundaries must arrive promptly.
                if mark in ('begin', 'unfold', 'end') and not 0 <= time.time() - timestamp < 2:
                    raise RuntimeError('Capture marker delivery was delayed; recapture on an idle simulator')
                marks.add(mark)
                times[mark] = timestamp
                if mark == 'begin':
                    recorder = Recorder(udid, cover, 'LCD')
                elif mark == 'unfold':
                    recorder.stop()
                    set_posture(udid, 'open')
                    recorder = Recorder(udid, inner, 'LCD-1')
                    inner_start = recorder.started
                elif mark == 'end' and recorder is not None:
                    recorder.stop()
                    recorder = None
            result = process.wait()
        if result or marks != {'begin', 'unfold', 'resume', 'end'}:
            raise RuntimeError(f'{test} failed (exit {result}, marks {marks}); see {raw / f"{name}.log"}')
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait()
        if recorder is not None:
            recorder.stop()
    for variant, size, framed in [('store', preview, False), ('social', UNFOLD_SOCIAL, True)]:
        joined = raw / f'{name}-{variant}.mp4'
        composed = run('uv', 'run', HERE / 'unfold.py', '--cover', cover, '--inner', inner,
                       '--cover-seconds', f'{times["unfold"] - times["begin"]:.3f}',
                       '--inner-start', f'{max(0.0, times["resume"] - inner_start):.3f}',
                       '--inner-seconds', f'{times["end"] - times["resume"]:.3f}', '--size', f'{size[0]}x{size[1]}',
                       '--appearance', look, *(['--framed'] if framed else []), '--output', joined, check=False)
        if composed.returncode:
            raise RuntimeError(f'unfold.py failed:\n{composed.stderr}')
        seconds = float(run('ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                            '-of', 'default=noprint_wrappers=1:nokey=1', joined).stdout)
        destination = (output / 'iphone-duo' / f'{name}.mp4' if variant == 'store'
                       else output / 'social' / f'{name}-duo-{size[0]}x{size[1]}.mp4')
        destination.parent.mkdir(parents=True, exist_ok=True)
        seconds = encode(joined, destination, size, 0, seconds, PAD[look], limits)
        print(f'  {destination.relative_to(HERE)} {size[0]}x{size[1]} {seconds:.1f}s', flush=True)


def encode(raw, output, size, start, duration, pad, limits):
    """Trim [start, start+duration) of a variable-rate capture to constant 30 fps H.264 with silent stereo AAC."""
    width, height = size
    # XCTest event delivery slows down on busy hosts. Preserve every action while
    # allowing modest acceleration, and reject tours that would become unreadable.
    output_duration = min(duration, limits[1] - 0.25)
    speed = duration / output_duration
    if speed > 1.5:
        raise RuntimeError(f'Tour requires {speed:.2f}x playback to fit {limits}; recapture on an idle simulator')
    run('ffmpeg', '-y', '-loglevel', 'error', '-i', raw, '-f', 'lavfi', '-i',
        'anullsrc=channel_layout=stereo:sample_rate=44100', '-filter_complex',
        f'[0:v]tpad=stop_mode=clone:stop_duration=5,'
        f'trim=start={start:.3f}:duration={duration:.3f},setpts=(PTS-STARTPTS)/{speed:.8f},fps=30,'
        f'scale={width}:{height}:force_original_aspect_ratio=decrease:flags=lanczos,'
        f'pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color={pad},setsar=1[v]',
        '-map', '[v]', '-map', '1:a', '-t', f'{output_duration:.3f}',
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
    parser.add_argument('--only', choices=[name for name, _ in SHOTS] + [name for name, _, _ in TOURS] + [UNFOLD[0]], action='append', help='Only this screenshot or tour name (repeatable)')
    parser.add_argument('--keep-booted', action='store_true')
    parser.add_argument('--settle', type=float, default=9,
                        help='Seconds each screenshot launch settles before capture (raise on a busy host)')
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
        profile = DEVICES[family]
        d = device(profile['simulator']); udid = d['udid']; started = d['state'] != 'Booted'
        raw = HERE / 'raw' / family; output = HERE / 'output'
        try:
            if started:
                sim('boot', udid)
            sim('bootstatus', udid, '-b')
            if profile.get('posture'):
                set_posture(udid, profile['posture'])
            display_args = [f'--display={profile["display"]}'] if profile.get('display') else []
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
                    time.sleep(args.settle)
                    path = raw / appearance / f'{filename}.png'
                    sim('io', udid, 'screenshot', '--type=png', *display_args, path)
                    print(f'  {path.relative_to(HERE)} {"x".join(map(str, png_size(path)))}', flush=True)
                sim('terminate', udid, bundle, check=False)
            if args.video and profile['preview']:
                look = args.video_appearance
                sim('ui', udid, 'appearance', look)
                (raw / 'video').mkdir(parents=True, exist_ok=True)
                for name, test, limits in TOURS:
                    if not wanted(name):
                        continue
                    print(f'Recording {family} {look}: {name} ({test})…', flush=True)
                    source = raw / 'video' / f'{name}.mp4'
                    begin, end = record_tour(udid, test, source, look, profile.get('display'))
                    start, duration = begin, end - begin
                    preview = output / family / f'{name}.mp4'
                    preview.parent.mkdir(parents=True, exist_ok=True)
                    size = profile['preview']
                    seconds = encode(source, preview, size, start, duration, PAD[look], limits)
                    print(f'  {preview.relative_to(HERE)} {size[0]}x{size[1]} {seconds:.1f}s', flush=True)
                    if not profile['social']:
                        continue
                    social = output / 'social' / f'{name}-{SOCIAL[0]}x{SOCIAL[1]}.mp4'
                    social.parent.mkdir(parents=True, exist_ok=True)
                    encode(source, social, SOCIAL, start, duration, PAD[look], limits)
                    print(f'  {social.relative_to(HERE)} {SOCIAL[0]}x{SOCIAL[1]} {seconds:.1f}s', flush=True)
                if profile.get('unfold_clip') and wanted(UNFOLD[0]):
                    record_unfold(udid, raw / 'video', output, look, profile['preview'])
        finally:
            sim('terminate', udid, bundle, check=False)
            sim('status_bar', udid, 'clear', check=False)
            if started and not args.keep_booted:
                sim('shutdown', udid, check=False)
        if any(wanted(name) for name, _ in SHOTS):
            for variant, size in profile['renders']:
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
