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
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.healthy)
                    Text(isSchedule ? "TONIGHT'S SCHEDULE" : "ACTIVE CURVE")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(Theme.healthy)
                        .tracking(1)
                }

                Spacer()

                Text("until \(session.wakeTimeFormatted)")
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
            }

            // Set point chart
            if !chronologicalPoints.isEmpty {
                let totalSpan = totalMinuteSpan
                Chart {
                    ForEach(Array(chronologicalPoints.enumerated()), id: \.offset) { _, sp in
                        let x = minuteOffset(sp.time)
                        LineMark(
                            x: .value("Time", Double(x)),
                            y: .value("°F", sp.temperature)
                        )
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }

                    // "Now" vertical line at actual clock position
                    let nowX = Double(nowMinuteOffset)
                    RuleMark(x: .value("Now", nowX))
                        .foregroundStyle(Theme.amber.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .chartXScale(domain: 0...Double(totalSpan))
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: xTickMinutes.map { Double($0) }) { value in
                        AxisValueLabel {
                            if let mins = value.as(Double.self) {
                                Text(minuteOffsetToLabel(Int(mins)))
                                    .font(.system(size: 8))
                                    .rotationEffect(.degrees(-45))
                            }
                        }
                        .foregroundStyle(Theme.textMuted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisValueLabel()
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(height: compact ? 80 : 100)
                .padding(.bottom, 16)
            }

            // Stop button (only for run-once, not recurring schedules)
            if !isSchedule {
                Button {
                    isCancelling = true
                    onCancel()
                } label: {
                    HStack(spacing: 6) {
                        if isCancelling {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10))
                        }
                        Text(isCancelling ? "Stopping…" : "Stop Curve")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 8 : 10)
                    .background(Theme.error.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isCancelling)
            }
        }
        .padding(12)
        .background(Theme.healthy.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.healthy.opacity(0.2), lineWidth: 1)
        )
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
