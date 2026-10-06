import SwiftUI

struct SleepSummaryCardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let record: SleepRecord
    let score: Int?
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
            : AnyLayout(HStackLayout(spacing: 18))
        layout {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 6)
                Circle().trim(from: 0, to: Double(max(0, min(100, score ?? 0))) / 100)
                    .stroke(Theme.green, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(score.map(String.init) ?? "—").font(.mono(24, relativeTo: .title2)).lineLimit(1).minimumScaleFactor(0.5)
            }
            .padding(6)
            .frame(width: 78, height: 78)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sleep quality \(score.map(String.init) ?? "unavailable")")
            VStack(alignment: .leading, spacing: 5) {
                Text(DisplayTime.duration(record.sleepPeriodSeconds)).font(.mono(28, weight: .light, relativeTo: .title))
                    .minimumScaleFactor(0.7).lineLimit(1)
                Text("\(record.bedtimeFormatted) → \(record.wakeTimeFormatted)")
                    .font(.mono(12, relativeTo: .caption)).foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 0)
        }
        .cardStyle(vertical: 18, horizontal: 18)
    }
}
