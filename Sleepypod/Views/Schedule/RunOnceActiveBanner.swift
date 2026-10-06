import SwiftUI
import Charts

/// Banner showing an active run-once session with set point timeline and cancel button.
struct RunOnceActiveBanner: View {
    let session: RunOnceSession
    let onCancel: () -> Void
    var compact: Bool = false
    var isSchedule: Bool = false

    @State private var isCancelling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(isSchedule ? "TONIGHT · SCHEDULE" : "RUN ONCE · ACTIVE")
                Spacer(minLength: 8)
                Text("\(DisplayTime.clock(session.setPoints.first?.time ?? "22:00")) → \(session.wakeTimeFormatted)")
                    .font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2)
            }
            TemperatureCurve(points: session.setPoints, bedtime: session.setPoints.first?.time ?? "22:00", wake: session.wakeTime, compact: compact)
            if !isSchedule {
                Button(action: onCancel) {
                    Text("Stop").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36)
                        .background(Theme.active, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop run-once curve")
            }
        }
        .cardStyle()
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(isSchedule ? Theme.border1 : Theme.green, lineWidth: 1))
    }

    // MARK: - Time math (minutes-from-anchor, handles overnight)

    private var anchorMinutes: Int {
        guard let first = session.setPoints.first else { return 0 }
        return clockMinutes(first.time)
    }

    private func clockMinutes(_ time: String) -> Int {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return 0 }
        return h * 60 + m
    }

    /// Minutes elapsed since the curve's first set point, wrapping at midnight.
    private func minuteOffset(_ time: String) -> Int {
        return (clockMinutes(time) - anchorMinutes + 1440) % 1440
    }

    /// Sort set points by overnight offset (left-to-right = evening → morning).
    private var chronologicalPoints: [RunOnceSetPoint] {
        session.setPoints.sorted { minuteOffset($0.time) < minuteOffset($1.time) }
    }

    /// Total span in minutes from first to last point.
    private var totalMinuteSpan: Int {
        guard let last = chronologicalPoints.last else { return 1 }
        return max(minuteOffset(last.time), 1)
    }

    /// Where "now" falls on the minute-offset axis.
    private var nowMinuteOffset: Int {
        let cal = Calendar.current
        let nowMins = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        return (nowMins - anchorMinutes + 1440) % 1440
    }

    /// 4 evenly spaced tick positions in minute-offsets, mapped back to clock times.
    private var xTickMinutes: [Int] {
        let span = totalMinuteSpan
        guard span > 0 else { return [0] }
        let n = 4
        return (0..<n).map { i in i * span / (n - 1) }
    }

    /// Convert a minute-offset back to "7 PM" display label.
    private func minuteOffsetToLabel(_ offset: Int) -> String {
        let totalMins = (anchorMinutes + offset) % 1440
        let h = totalMins / 60
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let ampm = h < 12 ? "AM" : "PM"
        return "\(hour12) \(ampm)"
    }

    private var yDomain: ClosedRange<Double> {
        let temps = session.setPoints.map(\.temperature)
        guard let lo = temps.min(), let hi = temps.max() else { return 65...85 }
        return (lo - 2)...(hi + 2)
    }
}
