# ADR-006: Status Notifications in Top Nav Bar

## Status
Accepted

## Context
The app needs to show ongoing system status (priming, alarms, connection state) without interrupting the user's primary interaction. Full-width alert banners below the controls push content down, obscure the temperature dial, and feel disproportionate for background processes.

## Decision
Use compact inline indicators in the top nav bar for non-blocking status:

- **Priming**: pulsing blue drop icon + "Priming" text, left side of nav bar
- **Alarm**: handled separately as a full banner (requires immediate action)
- **Connection**: step-by-step timeline on disconnected screen (blocking)

### Placement rules
| Urgency | Placement | Example |
|---------|-----------|---------|
| Background process | Top nav bar, compact | Priming, syncing |
| Needs attention | Inline card in content | Calibration warning |
| Requires action | Full banner with buttons | Active alarm (stop/snooze) |
| Blocking | Full screen | Disconnected, loading |

### Design principles
- The top nav bar has two slots: left (status) and right (profile avatar)
- Status indicators are small, non-interactive, and auto-dismiss when done
- Only one status indicator at a time in the nav bar — priority: alarm > priming > syncing
- Pulsing animations indicate ongoing processes
- Consistent iconography: drop for water/priming, antenna for connection

## Consequences
- Nav bar stays compact — no stacking of multiple banners
- Background processes don't displace primary content
- Users can glance at the top to see system state without scrolling
- Future: push notifications for events when app is backgrounded (ios#4)
- The alarm banner is the exception — it's urgent enough to warrant full width with action buttons
