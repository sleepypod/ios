# Watch movement recordings

The sleepypod Watch app records wrist acceleration overnight and sends a summary to the iPhone. The training workspace (sleepypod/training) uses it as automatic movement labels for the pod's movement classifier. Watch motion is a label for *movement*, never a sleep-stage feature: Watch sleep stages are partly derived from the same accelerometer.

## How a recording happens

1. At bedtime, open sleepypod on the Watch, choose a duration (1–12 h) and tap **Record tonight**. The app asks for Motion & Fitness the first time. It calls `CMSensorRecorder.recordAccelerometer(forDuration:)`; the system records at 50 Hz in the background, so the app can close.
2. In the morning, tap **Send to iPhone**. The Watch reads the recorded span with `accelerometerData(from:to:)`, summarizes it and queues the file with WatchConnectivity `transferFile`, which retries until the iPhone receives it.
3. On the iPhone, the file appears under **Settings → Watch movement**, stored in Application Support/WatchMotion. Share it to a computer from there. Nothing is uploaded automatically.

## File format (`watch-motion-v1`)

JSON, named `watch-motion-<recordedFromMs>.json`, keys sorted.

| Field | Type | Meaning |
| --- | --- | --- |
| `version` | string | `watch-motion-v1` |
| `recordedFromMs`, `recordedToMs` | integer | Requested span, Unix milliseconds (UTC) |
| `timeZone` | string | IANA zone of the Watch at the start, for example `America/Los_Angeles` |
| `utcOffsetSeconds` | integer | That zone's offset at `recordedFromMs` |
| `sampleRateHz` | number | Recorder rate, 50 |
| `binSeconds` | number | Bin width, 2 |
| `jerkThresholdGPerSecond` | number | Threshold for `movingSamples`, 1.0 |
| `device` | string | Watch model and watchOS version |
| `bins` | object | Columnar arrays, one entry per bin with readings |
| `raw` | array or absent | Optional `[unixMs, x, y, z]` readings in g; off by default |

`bins` columns, all the same length:

| Column | Unit | Meaning |
| --- | --- | --- |
| `startMs` | Unix ms | Bin start, aligned to Unix time (multiples of `binSeconds`) |
| `samples` | count | Readings in the bin (≈100 for a full 2 s bin) |
| `meanMagnitude` | g | Mean of \|a\| = √(x²+y²+z²), gravity included (≈1 at rest) |
| `magnitudeVariance` | g² | Population variance of \|a\| in the bin |
| `maxJerk` | g/s | Largest \|Δ\|a\|\| / Δt between consecutive readings ≤ 0.5 s apart |
| `movingSamples` | count | Readings whose jerk exceeds `jerkThresholdGPerSecond` |

Bins with no readings are omitted: a missing bin means no data, never stillness. Times are the recorder's wall-clock `startDate` for each reading.

## Limits

- Not yet verified on a real Watch overnight: background recording, battery cost and delivery are untested.
- The system keeps recorded data for about three days; send it the next morning.
- One request records at most 12 hours.
- A night of 2 s bins is a few hundred kilobytes; raw 50 Hz readings are tens of megabytes, so raw export is off by default.
- The pod clock and the Watch clock are independent; the training workspace aligns them by recorded time and should check the offset against known events such as getting into bed.
