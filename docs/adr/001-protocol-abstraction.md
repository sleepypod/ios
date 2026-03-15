# ADR-001: Protocol Abstraction for Multi-Backend Support

## Status
Accepted

## Context
The app needs to support two backends: the legacy free-sleep REST API and the new sleepypod-core tRPC API. Both control the same hardware but have different data shapes, authentication, and transport.

## Decision
Define a single `SleepypodProtocol` that all backends conform to. Managers (DeviceManager, ScheduleManager, etc.) depend on the protocol, never on concrete clients. Backend switching is handled by `APIBackend.createClient()`.

## Consequences
- Adding a new backend (e.g., cloud API) requires only implementing the protocol
- All views are backend-agnostic — no conditional logic in UI code
- Data mapping between API shapes and shared models happens inside each client
- Trade-off: some features only exist on one backend (e.g., calibration on core only)
