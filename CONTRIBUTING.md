# Contributing

Thanks for helping with sleepypod. A few things to know before opening a pull request.

## Licensing of contributions

The source is [AGPL-3.0](LICENSE). The App Store build is also distributed by the copyright holder under the App Store exception described in the [License section of the README](README.md#license). For that exception to keep working, the copyright holder must be able to grant Apple's distribution terms for every line in the binary.

So, by submitting a contribution you agree that:

1. You wrote it, or have the right to submit it, under the terms of the AGPL-3.0 (the [Developer Certificate of Origin](https://developercertificate.org)). Sign off each commit with `git commit -s`.
2. You grant Jonathan Ng a perpetual, worldwide, non-exclusive, royalty-free licence to distribute your contribution as part of sleepypod through the Apple App Store and TestFlight under Apple's terms, in addition to the AGPL-3.0.

Your contribution stays AGPL-3.0 for everyone else; this only lets the App Store build keep shipping.

## Workflow

- Branch from `dev`; PRs target `dev`. `main` is release-only and tagged by semantic-release from conventional commit messages (`feat:`, `fix:`, `chore:` …).
- `xcodegen generate` after adding or moving files; the `.xcodeproj` is tracked but generated from `project.yml`.
- `swiftlint --strict` must pass. Unit tests live in `SleepypodTests` (Swift Testing), UI and screenshot tests in `SleepypodUITests`.
- Every PR needs a test plan, even if it is manual steps on a real pod.
- User-facing copy writes the brand as lowercase `sleepypod` and does not name third-party hardware brands except in the compatibility line.
