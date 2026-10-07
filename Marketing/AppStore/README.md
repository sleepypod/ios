# sleepypod App Store marketing assets

Capture the real app in the simulator, render framed App Store screenshots,
and record app-preview clips plus a full walkthrough video.

```sh
python3 Marketing/AppStore/capture.py --video
```

Run from the repository root. Requires Xcode with an iPhone 17 Pro Max
device type and an installed iOS runtime, `uv`, and `ffmpeg`/`ffprobe`. No desktop taps or window positioning
are required. The script builds the Debug app and UI tests into
`build/marketing`, creates or reuses a dedicated `sleepypod Marketing` simulator,
and reinstalls sleepypod there (only that capture simulator's app data is reset), captures eight screens in dark and light, records the tours, and
renders the compositions. It pins the status bar to 9:41 with full battery and
Wi-Fi, clears the override afterwards, and shuts down only simulators it
booted. A full run with video takes about 10 minutes.

Options: `--skip-build` (reuse the last marketing build), `--device iphone-6.9`,
`--appearance dark|light` (repeatable; default both), `--video-appearance`
(default `dark`), `--only NAME` (repeatable; a screenshot or tour name such as
`04-schedule` or `clip-schedule`; only selected screenshots are rendered), `--keep-booted`. Omit `--video` to produce
screenshots only.

| Output | Dimensions | Content |
| --- | --- | --- |
| `output/iphone-6.9/dark/*.png` | 1320×2868 | Primary App Store set: eight framed screens |
| `output/iphone-6.9/light/*.png` | 1320×2868 | Same eight screens in light mode |
| `output/iphone-6.5/{dark,light}/*.png` | 1284×2778 | 6.5-inch renders of the same captures |
| `output/iphone-6.9/clip-*.mp4` | 886×1920 | 16–20 s app previews (temperature, Night & Dawn, schedule, sleep → Watch) |
| `output/iphone-6.9/walkthrough-sleepypod.mp4` | 886×1920 | ~100 s tour of every tab, each control, the Watch page and Health |
| `output/social/*-1080x1920.mp4` | 1080×1920 | Each video letterboxed for social, padded with the app background |

Videos use H.264 High, 30 fps, yuv420p, and a silent AAC stereo track, following
[Apple's app preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications).
App Store Connect accepts previews of 15–30 s, so only the `clip-*` files are
uploadable; the walkthrough is for the web and social. Each video has an
adjacent JSON file with its ffprobe properties, and `capture.py` asserts size,
codec, frame rate, audio and duration before writing it. Raw captures and
generated deliverables are local and ignored by Git.

## Upload checks (reviewed October 7, 2026)

The shipping target is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`). Apple currently
names Dynamic Island medium (1206×2622 or 1179×2556) as the required screenshot
slot and documents scaled fallbacks from other iPhone sizes. This pipeline
produces the large-display and 6.5-inch sets above; check inherited assets in
App Store Connect's Media Manager before submission and add a medium-size export
if the slot is not covered. Generated files do not establish upload acceptance.
See [Apple's current screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

The preview dimensions match Apple's current specification. Dedicated product-page
header and search artwork are not generated here; inspect those optional placements
separately if used. No assets are uploaded or submitted by these scripts.

## Capture states

Every capture launches the Debug app with `-apiBackend demo` (synthetic pod
data, no network), `-onboardingComplete YES`, `-healthSyncEnabled NO` and
`-marketingCapture YES`, which skips the notification prompt and hides the
DEMO badge. The `-uiRoute` and `-tempControl` arguments choose the screen:

| Screenshot | Launch arguments |
| --- | --- |
| `01-temperature` | `-tempControl dial` |
| `02-both-sides` | `-tempControl sides` |
| `03-night-dawn` | `-tempControl stepper` |
| `04-schedule` | `-uiRoute schedule` |
| `05-sleep-night` | `-uiRoute sleep` (last night: stages, HR, HRV, breathing) |
| `06-sleep-week` | `-uiRoute weektrend` (Week, scrolled to the Watch agreement trend) |
| `07-apple-watch` | `-uiRoute watch` (Compare with Apple Watch) |
| `08-apple-health` | `-uiRoute onboard3 -apiBackend sleepypod-core -onboardingComplete NO` (Health step of setup) |

The `uiRoute` and `marketingCapture` hooks are compiled out of Release builds;
the other arguments override existing app preferences for this capture launch. Demo vitals are
generated per launch, so scores and averages differ slightly between runs.

Videos come from `SleepypodUITests/MarketingTour.swift`. Each test launches the
app with the same arguments, paces taps, dial drags and scrolls, and prints
`MARKETING_MARK begin|end <epoch>`. `capture.py` runs it with
`xcodebuild test-without-building` while `simctl io recordVideo` records, then
trims the recording to those marks. The tests skip unless the runner sees
`MARKETING_TOUR=1`, so normal test runs do not execute them. To run one by hand:

```sh
TEST_RUNNER_MARKETING_TOUR=1 xcodebuild test -project Sleepypod.xcodeproj -scheme Sleepypod \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:SleepypodUITests/MarketingTour/testWalkthrough
```

Inspect every output before uploading: watch each video end to end and open
every PNG. Content scrolls under the floating tab bar as it does in the app
(the heart-rate card on the Watch page, for example), and the Week screen is
captured scrolled, so its segmented control sits under the navigation bar.
Rebuild after code changes; `--skip-build` intentionally reuses the last
marketing binary. The upload build remains separate from this Debug capture build.

## Render existing captures

```sh
uv run Marketing/AppStore/generate.py --manifest Marketing/AppStore/manifest.iphone-6.9.json
uv run Marketing/AppStore/generate.py --manifest Marketing/AppStore/manifest.iphone-6.5.json --size 1284x2778
uv run Marketing/AppStore/generate.py --manifest Marketing/AppStore/manifest.example.json --check-config
uv run Marketing/AppStore/generate.py --manifest Marketing/AppStore/manifest.example.json --self-test
```

Captions, eyebrows and both palettes live in the manifests; `{appearance}` in
a path expands to `dark` or `light`, and `--appearance` renders one set. The
renderer keeps the full screen inside a drawn phone frame under the caption,
on a night-sky gradient taken from the app icon and the app's `indigo`/`violet`
colours. The app icon is read from the asset catalog and checked against
`pixel_sha256`, so an icon change is noticed before it reaches a store image.
`--check-config` validates the manifest, icon, lowercase brand and caption fit
without raw captures; `--self-test` renders a mock capture in each appearance
and verifies size and RGB/no-alpha output.

Store copy lives in [`metadata.md`](metadata.md).
