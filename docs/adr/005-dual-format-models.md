# ADR-005: Dual-Format Decodable Models

## Status
Accepted

## Context
The free-sleep API uses snake_case keys and unix timestamps. The sleepypod-core API uses camelCase keys, ISO8601 date strings, and superjson Date metadata. Both backends need to decode into the same Swift model types.

## Decision
Each model (VitalsRecord, SleepRecord, MovementRecord) implements custom `init(from:)` that:
1. Tries camelCase keys first (sleepypod-core)
2. Falls back to snake_case keys (free-sleep)
3. Parses timestamps as either Int (unix) or String (ISO8601)

For tRPC queries, the client sends `meta.values` annotations for Date fields so superjson can deserialize them.

## Example
```swift
// Handles both: {"heart_rate": 65} and {"heartRate": 65}
heartRate = try c.decodeIfPresent(Double.self, forKey: .heartRate)
    ?? c.decodeIfPresent(Double.self, forKey: .heart_rate)
```

## Consequences
- Single model type works with both backends — no duplication
- Custom decode is more code than auto-synthesized Codable
- Future: OpenAPI codegen would generate core-only types, and free-sleep mapping would be in FreeSleepClient only
- tRPC superjson date handling adds complexity to the query method
