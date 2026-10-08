# sleepypod {version}

TODO: one-line summary — what kind of release, headline PRs, and which branch/tag it was cut from.

Every App Store Connect field is below, ready to paste. Character limits are in brackets; give exact counts.

## App Information

Unchanged from the previous version unless noted (name, subtitle, bundle ID, SKU, categories, age rating, copyright). Copy the table from the previous file and edit what changed.

## Version Information ({version})

### Promotional Text [170]

```
TODO (or copy the previous one and mark "unchanged")
```

### Description [4000]

```
TODO (copy the previous one; edit only for features that changed)
```

### Keywords [100]

```
TODO
```

### What's New [4000]

```
TODO: one headline line, then 3–5 "•" bullets for customers.
```

### URLs

Unchanged unless noted: support, marketing, privacy policy.

### Screenshots and previews

TODO: which sets in `Marketing/AppStore/output/` go in which ASC slot; note if any captured screen changed and the set was regenerated.

## App Privacy

Unchanged unless the app starts collecting something.

## App Review Information

### Notes [4000]

```
TODO: copy the previous notes and add a NEW IN {version} section — what changed that a reviewer should know, and how to reach it in demo mode.
```

## TestFlight

### What to Test

```
- TODO: one bullet per change testers should exercise, on a real pod where it matters.
- Light and dark mode throughout.
```

## Verification

- TODO: unit test result at `{commit}` (count, date); UI test result.
- TODO: real-pod check (which pod/core version) or "simulator and demo only".

## Distribution

- Source: `{tag or branch}` at `{commit}`; version {version}, build {build}.
- Organizer: `~/Library/Developer/Xcode/Archives/{date}/sleepypod-{version}-{build}.xcarchive`.
- Bundle ID `com.jonathanng.com.ios.sleepypod`; export compliance declared exempt in Info.plist.
