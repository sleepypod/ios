# App Store metadata

Name, subtitle, description, keywords, review notes and privacy answers live in
[`metadata/app_store_submission.md`](../../metadata/app_store_submission.md),
with the plain-text copies beside it in [`metadata/`](../../metadata/).

The screenshot captions here (`manifest.*.json`) follow the same feature order:
temperature, both sides, Night & Dawn, schedule, sleep, weekly trends,
Apple Watch comparison, Apple Health. Keep the brand lowercase ("sleepypod")
in captions and promotional text; `generate.py --check-config` rejects a
capitalised brand in a caption.

Upload the dark set (`output/iphone-6.9/dark`, and `output/iphone-6.5/dark`
if a 6.5-inch set is needed) as the single App Store Connect set; the light set
is for the website and social posts. App previews must be 15–30 s, so upload
`clip-*.mp4`, not the walkthrough.
