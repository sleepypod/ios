# Sleepypod iOS

Native iOS app for controlling and monitoring your [Sleepypod](https://github.com/sleepypod/core) — temperature control, sleep tracking, biometrics, and on-device analysis.

<p align="center">
  <img src="docs/images/temperature-control.png" width="280" alt="Temperature control" />
  <img src="docs/images/schedule.png" width="280" alt="Sleep schedule" />
  <img src="docs/images/sensors.png" width="280" alt="Sensor dashboard" />
</p>

<p align="center">
  <img src="docs/images/schedule-curves.gif" width="280" alt="Schedule curves" />
  <img src="docs/images/biometrics-sleep.gif" width="280" alt="Biometrics and sleep" />
  <img src="docs/images/discovery.gif" width="280" alt="Pod discovery" />
</p>

<p align="center">
  <img src="docs/images/status-services.gif" width="280" alt="Status and services" />
  <img src="docs/images/services-detail.gif" width="280" alt="Service details" />
</p>

<p align="center">
  <a href="https://discord.gg/UMmv5R6MXa">Discord</a> · <a href="https://github.com/sleepypod/ios/issues">Issues</a> · <a href="#setup">Setup</a>
</p>

---

## Features

### Temperature Control
- Radial dial with 1°F granularity and drag-to-set
- Ambient glow that pulses and changes color based on heating/cooling intensity
- Side selector with link mode (control both sides together)
- User profile with default side preference

### Biometrics
- Real-time heart rate, HRV, and breathing rate charts
- Interactive tap-to-inspect with zone annotations (resting/normal/elevated)
- On-device sleep stage classification (rule-based, Core ML ready)
- Sleep quality scoring based on stage distribution
- Raw data export to CSV
- Outlier filtering and data smoothing

### Scheduling
- Temperature curve editor with per-phase +/- controls
- AI-generated sleep curves with "use now" shortcut
- Alarm and bedtime time pickers
- Power schedule toggle
- Day-of-week and side selection
- Profile presets (Cool, Balanced, Warm)

### Status & Monitoring
- Service health dashboard with expandable categories
- Real-time wifi signal, water level, calibration status
- Sensor calibration per side (capacitance, piezo, temperature)
- On-device ML model inventory
- Internet access toggle (iptables firewall control)
- System log viewer (journalctl)
- mDNS network discovery

### Connection
- Automatic mDNS discovery (`_sleepypod._tcp`)
- Step-by-step connection progress UI
- Manual IP override fallback
- 10-second polling with pull-to-refresh

---

## Architecture

```text
SleepypodProtocol          <- shared interface for all backends
├── FreeSleepClient        <- legacy free-sleep REST API
└── SleepypodCoreClient    <- sleepypod-core tRPC API

DeviceManager              <- temperature, power, polling
ScheduleManager            <- schedules, alarms
StatusManager              <- service health, server status
SettingsManager            <- device config, timezone, temp format
MetricsManager             <- sleep records, vitals, movement
PodDiscovery               <- mDNS/Bonjour network discovery
SleepAnalyzer              <- on-device sleep stage classification
UserProfile                <- local user preferences
```

Any backend conforms to `SleepypodProtocol` and the entire app works — no view changes needed.

---

## Requirements

- iOS 26.0+
- Xcode 26+
- Swift 6.0
- A Sleepypod on the local network

## Setup

```bash
# Clone
git clone https://github.com/sleepypod/ios.git
cd ios

# Install dependencies
npm install

# Generate Xcode project (requires XcodeGen)
brew install xcodegen
xcodegen generate

# Open in Xcode
open Sleepypod.xcodeproj
```

### Build & Deploy

```bash
# Build for device
xcodebuild -scheme Sleepypod -destination 'platform=iOS,name=YOUR_DEVICE' \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID build

# Install via devicectl
xcrun devicectl device install app --device DEVICE_ID \
  ~/Library/Developer/Xcode/DerivedData/Sleepypod-*/Build/Products/Debug-iphoneos/Sleepypod.app
```

### Lint

```bash
# Check (same as CI)
npm run lint

# Auto-fix + check
npm run lint:fix
```

Requires SwiftLint: `brew install swiftlint`

### API Spec Sync

```bash
# Fetch the latest OpenAPI spec from a running pod
./scripts/sync-api-spec.sh 192.168.1.88
```

---

## Contract Testing

Every PR runs contract tests that validate iOS model types against the live sleepypod-core API:

1. Starts a sleepypod-core dev server
2. Snapshots tRPC endpoint responses
3. Decodes with Swift model types
4. Fails if any model change breaks API compatibility

Also runs daily to catch core-side drift.

```bash
# Run locally
cd contract-tests && swift test
```

---

## CI

All checks run on every PR and must pass before merge:

| Job | Runner | What it does |
|-----|--------|-------------|
| **build** | `macos-26` | `xcodebuild build` — catches compile errors |
| **lint** | `macos-15` | SwiftLint — enforces code style |
| **contract-test** | `macos-15` | Validates models against live core API |

---

## Project Structure

```text
Sleepypod/
├── Models/           # Codable types (dual-format: free-sleep + core)
├── Networking/       # API clients, protocol, endpoints
├── Services/         # Managers, discovery, ML analyzer, logging
├── Views/
│   ├── Temp/         # Temperature dial, controls, side selector
│   ├── Schedule/     # Schedule editor, phase blocks, day selector
│   ├── Data/         # Health screen, charts, raw data export
│   ├── Status/       # Service health, calibration, logs, network
│   └── Settings/     # Device settings, tap gestures
├── openapi.json      # Committed API spec
└── Info.plist        # Bonjour service type
```

---

## Documentation

- [Health Vitals Science](docs/health-vitals-science.md) — measurement principles, normal ranges, filtering, and references

### Architecture Decision Records

- [ADR-001](docs/adr/001-protocol-abstraction.md) — Protocol abstraction for multi-backend support
- [ADR-002](docs/adr/002-mdns-discovery.md) — mDNS/Bonjour for pod discovery
- [ADR-003](docs/adr/003-contract-testing.md) — Contract testing between iOS and core
- [ADR-004](docs/adr/004-on-device-ml.md) — On-device sleep analysis with Core ML
- [ADR-005](docs/adr/005-dual-format-models.md) — Dual-format Decodable models

---

## Support

Need help? Join the [Discord](https://discord.gg/UMmv5R6MXa) or [open an issue](https://github.com/sleepypod/ios/issues).

## Related

- [sleepypod/core](https://github.com/sleepypod/core) — server for pod hardware control, scheduling, biometrics processing, and API

## License

[AGPL-3.0](LICENSE)
