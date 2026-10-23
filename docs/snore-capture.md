# Snore capture

Opt-in, overnight snore detection with the iPhone microphone (Settings → Health →
Snore detection). It implements section 2 of the training repository's
[overnight capture plan](https://github.com/sleepypod/training/blob/main/docs/overnight-capture-implementation-plan.md).

## What runs

- `AVAudioSession` in the `record` category with the `audio` background mode, and an
  `AVAudioEngine` input tap.
- Each buffer goes, in memory only, to Apple's built-in sound classifier
  (`SNClassifySoundRequest(classifierIdentifier: .version1)`, 3 s windows, 0.5 overlap)
  and to a transient detector for bed-frame knocks. Capture refuses to start if the
  classifier's `knownClassifications` has no `snoring` label.
- A window opens a snore event at confidence ≥ 0.6. The event stays open while windows
  stay ≥ 0.4, and closes after two quieter windows. Events less than 3 s apart merge. An
  event's confidence is its peak classifier score, which is not a calibrated probability.
- Calls, alarms and other audio interruptions pause listening, with the gap recorded.
  An input device appearing or going away restarts the engine. App termination saves what exists. Denied or
  revoked microphone access stops capture with a pointer to Settings.

Raw audio, transcripts and embeddings are never written or sent. Nothing is uploaded;
the user exports a session file with the share sheet.

## Session file

`Application Support/Snore/snore-<captureId>.json`, saved every minute while listening
and on stop. The folder and files are excluded from iCloud and computer backups. All times are Unix milliseconds.

| Field | Meaning |
| --- | --- |
| `schemaVersion` | `sleepypod-snore-capture-v1` |
| `captureId` | random UUID for this session |
| `source` | `iphone-microphone` |
| `device`, `osVersion`, `appVersion`, `timeZone` | provenance |
| `startMs`, `endMs`, `stopReason` | session bounds; `stopReason` is `user`, `app terminated`, `failed: …`, or `app not running` when iOS ended the app mid-session and the next launch closed the file at the end of its last listening span |
| `sampleRate`, `channelCount` | microphone input format |
| `detectorVersion` | classifier plus thresholds, `apple-sound-classifier-v1+hysteresis-0.6-0.4` |
| `classifier` | identifier, label, window seconds, overlap, on/off thresholds |
| `coverage[]` | `{startMs, endMs}` spans the microphone was listening; no detection outside them means no recording, not no snoring |
| `interruptions[]` | `{startMs, endMs, reason}` |
| `events[]` | `{captureId, startMs, endMs, eventType: "snore", confidence, detectorVersion, labelOrigin: "predicted"}`, the training contract's event rows |
| `knocks[]` | knock onsets in the first and last 60 s, for pod clock sync |

Event times come from the audio buffers' host time, anchored to wall-clock time
once when capture starts.

## Limitations

- Overnight background behavior, battery use and detection precision in a real bedroom
  are not measured yet. The plan's consented calibration session is not built yet.
- Audio alone does not say who snored.
- Snoring is not a diagnosis of anything.
