# Release notes

One file per archive: `<version>-testflight.md` for a TestFlight build, `<version>-app-store.md` for an App Store submission. The file is the record of what went into the build, what testers should try, and the exact text pasted into App Store Connect.

## Cutting a release

1. Make sure the commit is on a branch that can see the latest `v*` tag (semantic-release cuts them on `main`). The marketing version comes from that tag; the build number is a minute stamp.
2. Archive with `set -o pipefail; scripts/archive.sh build/Sleepypod-<version>.xcarchive 2>&1 | tee build/archive-<version>.log`. The script prints the build number and the Organizer path.
3. Copy `TEMPLATE.md` to `<version>-testflight.md` (or `-app-store.md`) and fill it in. The PR list since the previous tag: `git log --oneline <previous-tag>..HEAD --merges`.
4. Upload from Organizer (Distribute App → TestFlight & App Store, or TestFlight Internal Only).
5. Paste the What to Test block into TestFlight's test notes, and for an App Store build the What's New and App Review notes into the version page.

## Evergreen copy

Description, keywords, support URL and the review boilerplate live in [`metadata/`](../../metadata) (`description.txt`, `app_store_metadata.txt`, `review_notes.txt`, `app_store_submission.md`). Edit them there and copy them into a release file when they change.

## Versioning

- Build number: `YYMMDDHHMM` from `scripts/archive.sh`; unique and monotonic without touching tracked files.
- Marketing version: latest `v*` tag, three-part semver. The static `MARKETING_VERSION` in `project.yml` is the dev/simulator default and the fallback when no tag is reachable.
- App Store Connect requires every new build's version to be ≥ the last uploaded one and the build number to be unique within a version.
