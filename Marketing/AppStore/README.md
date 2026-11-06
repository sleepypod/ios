# sleepypod App Store marketing assets

Capture the real app in the simulator, render framed App Store screenshots,
and record app-preview clips plus a full walkthrough video.

```sh
python3 Marketing/AppStore/capture.py --video
```

Run from the repository root. Requires Xcode with the iPhone 17 Pro Max, iPad Pro
13-inch (M5) and iPhone Duo device types and iOS runtimes for them, `uv`, and `ffmpeg`/`ffprobe`. No desktop taps or window positioning
are required. The script builds the Debug app and UI tests into
`build/marketing`, creates or reuses a dedicated `sleepypod Marketing` simulator per device,
and reinstalls sleepypod there (only that capture simulator's app data is reset), captures eight screens in dark and light, records the tours, and
renders the compositions. It pins the status bar to 9:41 with full battery and
Wi-Fi, clears the override afterwards, and shuts down only simulators it
booted. A full run with video takes about 10 minutes per device.

Options: `--skip-build` (reuse the last marketing build), `--device iphone-6.9|ipad-13|iphone-duo`
(repeatable; default all three, see [Devices](#devices)),
`--appearance dark|light` (repeatable; default both), `--video-appearance`
(default `dark`), `--only NAME` (repeatable; a screenshot or tour name such as
`04-schedule` or `clip-schedule`; only selected screenshots are rendered), `--keep-booted`, `--settle SECONDS` (default 9; raise it when a busy host leaves screens half loaded). Omit `--video` to produce
screenshots only.

| Output | Dimensions | Content |
| --- | --- | --- |
| `output/iphone-6.9/dark/*.png` | 1320×2868 | Primary App Store set: eight framed screens |
| `output/iphone-6.9/light/*.png` | 1320×2868 | Same eight screens in light mode |
| `output/iphone-6.5/{dark,light}/*.png` | 1284×2778 | 6.5-inch renders of the same captures |
| `output/ipad-13/{dark,light}/*.png` | 2064×2752 | 13-inch iPad set, captured on iPad Pro 13-inch (M5), in a tablet frame |
| `output/iphone-duo/{dark,light}/*.png` | 2007×2853 | iPhone Duo set, captured unfolded on the inner display, in a foldable frame |
| `output/iphone-6.9/clip-*.mp4` | 886×1920 | 16–20 s app previews (temperature, Night & Dawn, schedule, sleep → Watch) |
| `output/iphone-6.9/walkthrough-sleepypod.mp4` | 886×1920 | ~100 s tour of every tab, each control, the Watch page and Health |
| `output/ipad-13/*.mp4` | 1200×1600 | The same clips and walkthrough recorded on the iPad |
| `output/iphone-duo/*.mp4` | 886×1920 | The same clips and walkthrough recorded on the unfolded Duo, letterboxed |
| `output/social/*-1080x1920.mp4` | 1080×1920 | Each iPhone video letterboxed for social, padded with the app background |
| `output/artwork/{dark,light}/header-21x9-3840x1646.png` | 3840×1646 | Product-page header creative asset (temperature dial) |
| `output/artwork/{dark,light}/search-3x2-3840x2560.png` | 3840×2560 | Search-results creative asset (sleep night) |
| `output/artwork/{dark,light}/universal-16x9-5244x2950.png` | 5244×2950 | Universal creative asset, accepted in both placements |

Videos use H.264 High, 30 fps, yuv420p, and a silent AAC stereo track, following
[Apple's app preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications).
App Store Connect accepts previews of 15–30 s, so only the `clip-*` files are
uploadable; the walkthrough is for the web and social. Each video has an
adjacent JSON file with its ffprobe properties, and `capture.py` asserts size,
codec, frame rate, audio and duration before writing its metadata. If simulator
latency makes a tour too long, it preserves every action and accelerates playback
to just below the limit; anything requiring more than 1.5× speed fails and needs
a recapture on an idle simulator. Raw captures and
generated deliverables are local and ignored by Git.

## Devices

| `--device` | Simulator | Screenshots | Previews | Frame (`frame` in the manifest) |
| --- | --- | --- | --- | --- |
| `iphone-6.9` | iPhone 17 Pro Max | 1320×2868, plus a 1284×2778 render | 886×1920 | `phone` |
| `ipad-13` | iPad Pro 13-inch (M5) | 2064×2752 (`manifest.ipad-13.json`) | 1200×1600 | `tablet`: thicker bezel, tighter corners, front camera |
| `iphone-duo` | iPhone Duo | 2007×2853 (`manifest.iphone-duo.json`) | 886×1920 | `foldable`: the crease and hinge notches down the middle |

Each device gets its own `sleepypod Marketing — <simulator>` simulator on the newest
iOS runtime that supports that device type (a beta runtime may support only a few).
Sizes follow Apple's
[screenshot](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
and [app preview](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications)
specifications (reviewed November 6, 2026): the 13-inch iPad slot takes 2064×2752 and
1200×1600 previews; the iPhone Duo slot takes its inner display, 2007×2853, or its outer
display, 1398×2034, and the standard 886×1920 iPhone previews. Apple requires Duo
screenshots from April 2027 for apps built with the iOS 27.1 SDK or later.

simctl has no fold command, so `capture.py` builds `duo_hinge.m` for the simulator SDK into
`build/marketing` and runs it with `simctl spawn`: it posts the HID events Xcode's Device
Hub sends for its hinge slider and Rotate Left, opening the Duo flat with the inner display
upright, then checks with `devicectl` that the inner display (`LCD-1`) hosts the UI.
Screenshots and recordings name that display. The helper uses private simulator API and
never ships in the app. The iPad and Duo videos are recorded but not cut for social.

## Upload checks (reviewed October 7, 2026)

The app targets iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`). Apple currently
names Dynamic Island medium (1206×2622 or 1179×2556) as the required screenshot
slot and documents scaled fallbacks from other iPhone sizes. This pipeline
produces the large-display, 6.5-inch, 13-inch iPad and iPhone Duo sets above; check inherited assets in
App Store Connect's Media Manager before submission and add a medium-size export
if the slot is not covered. Generated files do not establish upload acceptance.
See [Apple's current screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

The preview dimensions match Apple's current specification. Product-page header and
search-results artwork come from `manifest.artwork.json` (see
[Creative assets](#creative-assets-reviewed-october-21-2026)). No assets are uploaded
or submitted by these scripts.

## Creative assets (reviewed October 21, 2026)

App Store Connect's optional *creative assets* lead the product page (header) and
replace the screenshot strip in search results on iOS 27 and iPadOS 27 and later;
older devices keep showing screenshots. Apple's
[creative assets specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)
accept, for images, exactly these placements:

| Placement | Ratio | Size | Format |
| --- | --- | --- | --- |
| Product page header | 21:9 | 3840×1646 | JPEG or PNG, no alpha |
| Search results | 3:2 | 1920×1280 to 3840×2560 | JPEG or PNG, no alpha |
| Universal (both placements) | 16:9 | 5244×2950 | PNG only, no alpha |

Video is accepted in the same placements (5–30 s, 30 or 60 fps) but is not produced
here. In-app event cards (1920×1080 to 3840×2160 and 1080×1920 to 2160×3840) are a
separate feature and need an event, so they are not generated. Assets are uploaded
on the version page under *Header and Search Results*, or ahead of time through the
Asset Library, as described in
[Manage your App Store assets](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets);
they go through their own review before they can be placed. Apple Ads has no
upload of its own: search results ads show the product page's screenshots or a
custom product page, and Today tab ads are built from a custom product page
([Create Today tab ads](https://searchads.apple.com/help/ad-creative/0086-create-today-tab-ads)),
so nothing extra is generated for Apple Ads.

Apple's [asset best practices](https://developer.apple.com/app-store/asset-best-practices/)
ask for one clear idea, focal content centred within a safe area, and no pricing,
URLs, copyright marks, unverified awards or Apple badges. Apple publishes no safe-area
pixel values outside its Figma/Sketch templates; the manifests use measured
margins instead (header and search 9 % of the width and 8 % of the height; universal
12 % and 14 %, since Apple shows roughly 84 % of its width in search and 76 % of its
height as a header). Icon, wordmark, caption and the phone's screen stay inside
that area; only the phone body bleeds off the bottom. `--guides` outlines the area
in red for proofing, and `--check-config` rejects pricing symbols, the words Apple's
guidance forbids, a capitalised brand, and any size that is not in the table above.
Preview the result in App Store Connect's product page preview before placing it.

```sh
uv run Marketing/AppStore/generate.py --manifest Marketing/AppStore/manifest.artwork.json
uv run Marketing/AppStore/generate.py --manifest Marketing/AppStore/manifest.artwork.json --guides --output-dir /tmp/artwork-guides/{appearance}
uv run Marketing/AppStore/generate.py --manifest Marketing/AppStore/manifest.artwork.json --check-config
uv run Marketing/AppStore/generate.py --manifest Marketing/AppStore/manifest.artwork.json --self-test
```

Upload the dark set; the light set is for the website. The header and universal
images frame the temperature dial, the search image frames the sleep night, both
from the same raw captures as the screenshots. A caption may contain `\n` to force
its line break.

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
| `08-apple-health` | `-uiRoute health` (Settings, Apple Health) |

The `uiRoute` and `marketingCapture` hooks are compiled out of Release builds;
the other arguments override existing app preferences for this capture launch. Demo vitals are
generated per launch, so scores and averages differ slightly between runs.

Videos come from `SleepypodUITests/MarketingTour.swift`. Each test launches the
app with the same arguments, paces taps, dial drags and scrolls, and prints
`MARKETING_MARK begin|end <epoch>`. `capture.py` runs it with
`xcodebuild test-without-building` and starts/stops `simctl io recordVideo` as
those flushed marks arrive. The test holds each endpoint screen for three seconds;
delayed marker delivery or recorder startup fails instead of exporting a Home-screen
transition. Video duration comes from the recording itself, avoiding differences
between recorder frame timing and host wall time. The tests skip unless the runner sees
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
uv run Marketing/AppStore/generate.py --manifest Marketing/AppStore/manifest.ipad-13.json --size 2064x2752
uv run Marketing/AppStore/generate.py --manifest Marketing/AppStore/manifest.iphone-duo.json --size 2007x2853
uv run Marketing/AppStore/generate.py --manifest Marketing/AppStore/manifest.example.json --check-config
uv run Marketing/AppStore/generate.py --manifest Marketing/AppStore/manifest.example.json --self-test
```

Captions, eyebrows and both palettes live in the manifests; `{appearance}` in
a path expands to `dark` or `light`, and `--appearance` renders one set. A manifest
with `screenshots` renders the portrait sets and one with `artwork` renders the
landscape creative assets. The
renderer keeps the full screen inside a drawn phone frame under the caption,
on a night-sky gradient taken from the app icon and the app's `indigo`/`violet`
colours. The app icon is read from the asset catalog and checked against
`pixel_sha256`, so an icon change is noticed before it reaches a store image.
`--check-config` validates the manifest, icon, lowercase brand and caption fit
without raw captures; `--self-test` renders a mock capture in each appearance
and verifies size and RGB/no-alpha output.

Store copy lives in [`metadata.md`](metadata.md).
