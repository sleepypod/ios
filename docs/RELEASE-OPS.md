# Release & App Store operations

## App Store Connect

- App record bundle ID is `com.jonathanng.com.ios.sleepypod` (note the doubled `com`). The shorter `com.jonathanng.ios.sleepypod` record was removed from ASC and cannot take builds; do not "fix" the ID again.
- Team `ZUR2343J7S`, automatic signing. Capabilities: HealthKit. No IAP, no push, no CloudKit.
- Export compliance: `ITSAppUsesNonExemptEncryption = false` in `Sleepypod/Info.plist` (HTTPS and local network only). Without it every build sits in "Missing Compliance".
- Privacy: Health data stays on device and in the user's Health store; local-network traffic goes only to the pod. `PrivacyInfo.xcprivacy` is in the app bundle.

## Archive

- **Use `scripts/archive.sh`, not Product → Archive.** It stamps `CURRENT_PROJECT_VERSION` with `YYMMDDHHMM` and takes `MARKETING_VERSION` from the latest reachable `v*` tag, as xcodebuild overrides, so no tracked file changes. It regenerates the pbxproj with XcodeGen first and copies the archive into Organizer's dated library. Don't run two archives in the same minute.
- Tags come from semantic-release on `main` (conventional commits). A branch cut before merge cannot see the newest tag and falls back to `project.yml`'s `MARKETING_VERSION`; cut release builds from `main` when the version matters.
- Record every archive in [`docs/releases/`](releases/README.md).

## TestFlight

- Internal testers (ASC team members) get builds without review, as soon as processing finishes.
- External testers: the first build, and any later build with notable changes, goes through Beta App Review. Test Information must point reviewers at **Explore demo** on first launch — they have no pod.

## Screenshots and previews

- `Marketing/AppStore/capture.py --video` regenerates the App Store screenshots, preview clips and the walkthrough (see its README). Re-run for any release that changes a captured screen.
