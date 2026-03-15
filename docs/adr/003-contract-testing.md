# ADR-003: Contract Testing Between iOS and Core

## Status
Accepted

## Context
The iOS app hand-writes Swift `Decodable` types to match the core API's tRPC responses. When the API changes (new fields, renamed keys, type changes), the app silently fails at runtime. We hit this with:
- tRPC v11 requiring `?input={"json":{}}` on all queries
- A new `s` field in gesture pairs
- superjson Date encoding requirements

## Decision
Run automated contract tests in CI that:
1. Start a sleepypod-core dev server
2. Snapshot actual tRPC responses from all endpoints
3. Decode them with the iOS Swift model types
4. Fail the PR if any decode breaks

Tests run on every PR (blocking merge) and daily (catching core-side drift).

## Consequences
- API drift is caught at CI time, not user-facing runtime
- Both repos must be public (for cross-repo checkout without PAT)
- Tests are integration tests — slower than unit tests (~2 min)
- Some endpoints may fail in CI (no hardware) — handled gracefully with null fixtures
- Future: replace hand-written types with OpenAPI codegen (ADR-004 pending)
