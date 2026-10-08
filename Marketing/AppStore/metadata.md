# App Store metadata

Use the selected version's document in [`docs/releases/`](../../docs/releases/)
for the paste-ready App Store Connect fields. See
[`docs/RELEASE-OPS.md`](../../docs/RELEASE-OPS.md) for the release workflow;
the older files in `metadata/` are background references.

The screenshot captions here (`manifest.*.json`) follow the same feature order:
temperature, both sides, Night & Dawn, schedule, sleep, weekly trends,
Apple Watch comparison, Apple Health. Keep the brand lowercase ("sleepypod")
in captions and promotional text; `generate.py --check-config` rejects a
capitalised brand in a caption.

Upload the dark set (`output/iphone-6.9/dark`, and `output/iphone-6.5/dark`
if a 6.5-inch set is needed) as the single App Store Connect set; the light set
is for the website and social posts. App previews must be 15–30 s, so upload
`clip-*.mp4`, not the walkthrough.
