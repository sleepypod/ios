# Startup and core dev API audit

The iOS changes are implemented and verified locally. The running pod's log
endpoint is repaired; all 59 unit/live tests now pass without exclusions.

Core source reviewed: `origin/dev` at
`2e13b79b6643bfac4a3201195ff11c48e42f057f`. The neighboring working checkout was
not switched or edited. Its new startup changes retain the consumed contracts.
The live pod reports `perf/startup-api` at `aeb3852`, not current dev.

## Findings and changes

The main connection failure was decoding: powered-off pods legitimately return
null temperatures, which the app rejected. HTTP and WebSocket models now keep
missing readings. Ambient-light lux is also nullable; unavailable readings are
not displayed as fabricated measurements.

First status uses only device.getStatus, without diagnostics or shell-based
Wi-Fi queries. It consumes core's current level, alarm flag and Wi-Fi signal.
Discovery validates candidate APIs independently, saves only a verified address,
and avoids duplicate requests. Saved-address verification runs alongside
Bonjour/fallback discovery, retains priority over other pods, and is bounded to
three seconds before falling back. Old browser callbacks, cancelled requests,
manual entry, superseded scans and stale WebSocket sources cannot overwrite a
newer selection. Cached status belongs to its endpoint/backend and never claims
a live connection on launch.

Local Network policy denial gets an explicit explanation and Open Settings
button, with recovery when browsing becomes ready. Idle/failed discovery stops
showing a busy spinner. Notification authorization waits until connection.

API corrections:

- All 40 consumed tRPC procedures exist in current core dev. Direct callers in
  services/views now use the common transport, with bounded requests and server
  error messages. Query payloads escape reserved delimiters.
- Removed deleted biometrics.getProcessingStatus. Unsupported reboot/service
  operations report unsupported instead of priming hardware or pretending success.
- Alarm dismissal uses device.clearAlarm instead of power-off.
- Combined temperature/power-on sends temperature in one device.setPower call,
  avoiding the second call's default 75°F target.
- Overnight power schedules are retained in schedules.batchUpdate.
- Sleep-record edits include SuperJSON Date metadata.
- Unfiltered sleep/vitals/movement queries omit side rather than silently using left.
- CI checks core dev, runs unit/transport tests, and no longer swallows malformed
  device/calibration fixtures. Snapshot transport/HTTP failures fail the job,
  except an explicit device HTTP-500 allowance on hardware-free CI.

## Completion audit

| Requirement | Evidence | Result |
| --- | --- | --- |
| Fast usable first connection | Fresh simulator welcome → Connect → live controls; live discovery timings | Verified on this LAN/simulator |
| Saved-address reconnect and recovery | UI relaunch; live stale-address test; saved probe deadline | Verified |
| Cancellation/manual entry/overlapping scans | StartupTests regression cases and generation checks | Verified |
| Permission-state discoverability | SDK PolicyDenied constant, denial/recovery regression, Settings action | Verified state handling; no physical-phone denial test |
| Core endpoint names/methods/inputs | 40-procedure source audit, mutation request fixtures | Verified against dev source |
| Response decoding | 19 live read operations, live WS, null fixtures, seven package contracts | Verified |
| UI rendering | Fresh-install UI test plus reviewed screenshot | Verified |
| Build and regression gates | 59 unit/live tests, strict lint, device build with Swift warnings as errors | Passed |
| Live system.getLogs on .88 | HTTP success after targeted journal-access repair | Verified |

Physical iPhones have not been installed to or changed. No live control
mutations, full pod deployments, reboots or app releases were made. Core service
journal permissions were repaired and the service restarted over SSH port 8822.
The pre-existing `.serena/project.yml` changes were left alone.

## Evidence and reproduction

Final suite: `/tmp/sleepypod-journal-fixed.xcresult` — 59 passed, zero skipped,
including the live log endpoint. Earlier timing observations:
Empty-address discovery test: 0.229 s. Stale-address recovery test: 0.761 s.
These are observations on this LAN, not guarantees across network conditions.

Fresh-install/relaunch UI: `/tmp/sleepypod-ui-final.xcresult` — passed. Earlier
UI activity timestamps measured about two seconds from Connect tap to observing
controls (including XCTest polling). Reviewed unobstructed screenshot:
`/tmp/sleepypod-ui-final-images/C3C5FEF7-D42E-4DEB-8D81-79488D1BE90F.png`.

All read methods: `/tmp/sleepypod-all-reads.xcresult` — passed.
Live WebSocket: `/tmp/sleepypod-live-stream.xcresult` — passed.
Package contracts: `/tmp/sleepypod-contract-strict.log` — seven passed against
fresh .88 responses. Generated copies/fixtures were removed after verification.
Device build: `/tmp/sleepypod-release-check.log` — passed (host linker prints an
existing missing OpenSSL search-directory warning).

The unrelated sleep-analysis fixture was repaired without changing production
classification: five valid epochs isolate a ratio near 0.912, between the old
0.90 and tested 0.92 thresholds, from the separate rolling outlier filter.

```sh
TEST_RUNNER_POD_TEST_URL=http://192.168.1.88:3000 xcodebuild test \
  -project Sleepypod.xcodeproj -scheme Sleepypod \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SleepypodTests \
  CODE_SIGNING_ALLOWED=NO
```

UI tests require a freshly created simulator and TEST_RUNNER_POD_UI_TEST=1;
select only SleepypodUITests. They tap Connect and notification authorization,
then relaunch. They do not tap hardware controls.

## Journal-access repair and upstream fix

SSH root access on port 8822 confirmed that the sleepypod service lacked the
systemd-journal group. The Yocto image has no getent command, so the installer's
existing group checks silently failed. A persistent service drop-in at
/etc/systemd/system/sleepypod.service.d/journal-access.conf grants dac and
systemd-journal. After daemon-reload and a core service restart, system.getLogs
returned HTTP success. No firmware or branch deployment was needed.

The core fix is pushed as draft [PR #698](https://github.com/sleepypod/core/pull/698)
against dev, from the isolated sibling sleepypod-core-journal-fix worktree,
branch fix/yocto-journal-access. Repository pre-push checks passed (TypeScript,
ESLint with one existing warning, both schema checks, and related tests). Group lookup uses NSS when available
and falls back to /etc/group. Fresh installs include the correct groups;
startup maintenance appends missing journal membership without removing dac or
custom groups. Older OTA updaters install the new maintenance script before
starting core, so the repair applies on that first update too.

Five shell-behavior regression tests cover missing getent, exact group names,
adm fallback, NSS lookup, absent journal groups, idempotency and repair failure.
A transient systemd service on .88 verified the actual root ExecStartPre →
unprivileged ExecStart transition: the helper appended systemd-journal while
preserving dac, and the unprivileged process successfully read the journal.
The temporary helper was used only for this verification; the persistent
service drop-in remains the targeted runtime repair.
