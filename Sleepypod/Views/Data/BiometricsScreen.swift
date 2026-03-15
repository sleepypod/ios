import SwiftUI
import Charts

struct BiometricsScreen: View {
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(SettingsManager.self) private var settingsManager
    @State private var vitals: [VitalsRecord] = []
    @State private var isLoading = false
    @State private var selectedSide: Side = .left

    private var api: SleepypodProtocol {
        APIBackend.current.createClient()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Side picker
                HStack(spacing: 0) {
                    ForEach([Side.left, .right], id: \.rawValue) { side in
                        let isSelected = selectedSide == side
                        Button {
                            Haptics.tap()
                            selectedSide = side
                            Task { await fetchVitals() }
                        } label: {
                            Text(side.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(isSelected ? .white : Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(isSelected ? Theme.cooling : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if isLoading {
                    ProgressView()
                        .tint(Theme.accent)
                        .padding(40)
                } else if vitals.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 36))
                            .foregroundColor(Theme.textMuted)
                        Text("No biometric data yet")
                            .font(.subheadline)
                            .foregroundColor(Theme.textMuted)
                        Text("Data appears after spending time in bed")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(40)
                } else {
                    // Summary stats
                    summaryRow

                    // Heart Rate chart
                    chartCard(
                        title: "Heart Rate",
                        icon: "heart.fill",
                        color: Theme.error,
                        data: vitals.compactMap { v in
                            v.heartRate.map { (v.date, $0) }
                        },
                        unit: "BPM"
                    )

                    // HRV chart
                    chartCard(
                        title: "Heart Rate Variability",
                        icon: "waveform.path.ecg",
                        color: Theme.accent,
                        data: vitals.compactMap { v in
                            v.hrv.map { (v.date, $0) }
                        },
                        unit: "ms"
                    )

                    // Breathing rate chart
                    chartCard(
                        title: "Breathing Rate",
                        icon: "lungs.fill",
                        color: Theme.healthy,
                        data: vitals.compactMap { v in
                            v.breathingRate.map { (v.date, $0) }
                        },
                        unit: "BPM"
                    )

                    // Raw data count
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textMuted)
                        Text("\(vitals.count) raw data points")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                        Spacer()
                        Text("\(selectedSide.displayName) side")
                            .font(.caption2)
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
        .refreshable { await fetchVitals() }
        .task { await fetchVitals() }
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        HStack(spacing: 0) {
            let hrs = vitals.compactMap(\.heartRate)
            let hrvs = vitals.compactMap(\.hrv)
            let brs = vitals.compactMap(\.breathingRate)

            summaryItem(
                icon: "heart.fill",
                value: hrs.isEmpty ? "--" : "\(Int(hrs.reduce(0, +) / Double(hrs.count)))",
                unit: "BPM",
                color: Theme.error
            )
            Spacer()
            summaryItem(
                icon: "waveform.path.ecg",
                value: hrvs.isEmpty ? "--" : "\(Int(hrvs.reduce(0, +) / Double(hrvs.count)))",
                unit: "ms HRV",
                color: Theme.accent
            )
            Spacer()
            summaryItem(
                icon: "lungs.fill",
                value: brs.isEmpty ? "--" : "\(Int(brs.reduce(0, +) / Double(brs.count)))",
                unit: "BPM",
                color: Theme.healthy
            )
        }
        .cardStyle()
    }

    private func summaryItem(icon: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Text(unit)
                .font(.caption2)
                .foregroundColor(Theme.textMuted)
        }
    }

    // MARK: - Chart Card

    private func chartCard(title: String, icon: String, color: Color, data: [(Date, Double)], unit: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                Spacer()
                if let last = data.last {
                    Text("\(Int(last.1)) \(unit)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(color)
                }
            }

            if data.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
                    .padding(.vertical, 20)
            } else {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Time", point.0),
                            y: .value(title, point.1)
                        )
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        AreaMark(
                            x: .value("Time", point.0),
                            y: .value(title, point.1)
                        )
                        .foregroundStyle(color.opacity(0.1))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisValueLabel()
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(height: 150)
            }
        }
        .cardStyle()
    }

    // MARK: - Fetch

    private func fetchVitals() async {
        isLoading = vitals.isEmpty
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: end)!
        do {
            vitals = try await api.getVitals(side: selectedSide, start: start, end: end)
                .sorted { $0.date < $1.date }
        } catch {
            Log.network.error("Failed to fetch vitals: \(error)")
        }
        isLoading = false
    }
}
