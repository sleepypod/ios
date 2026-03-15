# ADR-002: mDNS/Bonjour for Pod Discovery

## Status
Accepted

## Context
Users had to manually enter the pod's IP address, which changes with DHCP leases and is not user-friendly.

## Decision
Use `NWBrowser` (Network framework) to discover `_sleepypod._tcp` services via Bonjour/mDNS. The pod advertises itself on the local network. The app auto-discovers and connects on launch, with manual IP as a fallback.

## Flow
1. App launches → tries saved IP first (fast path)
2. If saved IP fails or is empty → starts mDNS scan
3. Found pod → resolves IP via `NWConnection` → saves → connects
4. Manual override available in Settings

## Consequences
- Zero-config for most users — no IP entry needed
- Requires `NSLocalNetworkUsageDescription` and `NSBonjourServices` in Info.plist
- Requires the pod to run a Bonjour announcement service
- `NWBrowser` can't run in background — discovery is app-foreground only
