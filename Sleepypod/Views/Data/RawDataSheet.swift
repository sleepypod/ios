import SwiftUI

struct RawDataSheet: View {
    let vitals: [VitalsRecord]
    let smoothedVitals: [VitalsRecord]
    let metricsManager: MetricsManager

    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var fileCount: FileCount?

    private var side: String { metricsManager.selectedSide.rawValue }
    private var dropped: Int { vitals.count - smoothedVitals.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Stats
                    VStack(spacing: 6) {
                        statRow("Side", metricsManager.selectedSide.displayName)
                        statRow("Vitals records", "\(vitals.count)")
                        if dropped > 0 {
                            statRow("Outliers filtered", "\(dropped)", color: Theme.amber)
                        }
                        statRow("Sleep sessions", "\(metricsManager.sleepRecords.count)")
                        statRow("Movement records", "\(metricsManager.movementRecords.count)")

                        if let fc = fileCount {
                            Divider().background(Theme.cardBorder).padding(.vertical, 2)
                            statRow("Raw files (left)", "\(fc.rawFiles.left)")
                            statRow("Raw files (right)", "\(fc.rawFiles.right)")
                            statRow("Total size", fc.sizeDisplay)
                        }
                    }
                    .cardStyle()

                    // Files
                    VStack(spacing: 2) {
                        fileRow(
                            name: "vitals-\(side).csv",
                            rows: vitals.count,
                            icon: "heart.text.clipboard"
                        ) { exportVitals() }

                        Divider().background(Theme.cardBorder)

                        fileRow(
                            name: "sleep-\(side).csv",
                            rows: metricsManager.sleepRecords.count,
                            icon: "WelcomeLogo"
                        ) { exportSleep() }

                        Divider().background(Theme.cardBorder)

                        fileRow(
                            name: "movement-\(side).csv",
                            rows: metricsManager.movementRecords.count,
                            icon: "figure.walk"
                        ) { exportMovement() }
                    }
                    .cardStyle()

                    // Export all
                    Button { exportAll() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export All as CSV")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    // Info
                    Text("CSV files can be opened in Excel, Numbers, or imported into Python/R for analysis.")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Theme.background)
            .navigationTitle("Raw Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .task {
                fileCount = try? await APIBackend.current.createClient().getFileCount()
            }
        }
    }

    private func statRow(_ label: String, _ value: String, color: Color = Theme.textSecondary) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(Theme.textSecondary)
            Spacer()
            Text(value).font(.subheadline.monospaced()).foregroundColor(color)
        }
    }

    private func fileRow(name: String, rows: Int, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if icon == "WelcomeLogo" {
                        Image("WelcomeLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.accent)
                    }
                }
                .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.subheadline.monospaced())
                        .foregroundColor(.white)
                    Text("\(rows) rows")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                }

                Spacer()

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Theme.accent)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export

    private func exportVitals() {
        let csv = "id,side,timestamp,heartRate,hrv,breathingRate\n" +
            vitals.map { "\($0.id),\($0.side),\($0.date.ISO8601Format()),\($0.heartRate ?? 0),\($0.hrv ?? 0),\($0.breathingRate ?? 0)" }
                .joined(separator: "\n")
        share(csv, filename: "vitals-\(side).csv")
    }

    private func exportSleep() {
        let csv = "id,side,enteredBed,leftBed,durationSeconds,timesExited\n" +
            metricsManager.sleepRecords.map { "\($0.id),\($0.side),\($0.enteredBedDate.ISO8601Format()),\($0.leftBedDate.ISO8601Format()),\($0.sleepPeriodSeconds),\($0.timesExitedBed)" }
                .joined(separator: "\n")
        share(csv, filename: "sleep-\(side).csv")
    }

    private func exportMovement() {
        let csv = "timestamp,movement\n" +
            metricsManager.movementRecords.map { "\($0.timestamp),\($0.totalMovement)" }
                .joined(separator: "\n")
        share(csv, filename: "movement-\(side).csv")
    }

    private func exportAll() {
        // Combine all data into one CSV with sections
        var combined = "# Sleepypod Raw Data Export\n"
        combined += "# Side: \(metricsManager.selectedSide.displayName)\n"
        combined += "# Date: \(Date().ISO8601Format())\n\n"

        combined += "## Vitals\nid,side,timestamp,heartRate,hrv,breathingRate\n"
        combined += vitals.map { "\($0.id),\($0.side),\($0.date.ISO8601Format()),\($0.heartRate ?? 0),\($0.hrv ?? 0),\($0.breathingRate ?? 0)" }
            .joined(separator: "\n")

        combined += "\n\n## Sleep\nid,side,enteredBed,leftBed,durationSeconds,timesExited\n"
        combined += metricsManager.sleepRecords.map { "\($0.id),\($0.side),\($0.enteredBedDate.ISO8601Format()),\($0.leftBedDate.ISO8601Format()),\($0.sleepPeriodSeconds),\($0.timesExitedBed)" }
            .joined(separator: "\n")

        combined += "\n\n## Movement\ntimestamp,movement\n"
        combined += metricsManager.movementRecords.map { "\($0.timestamp),\($0.totalMovement)" }
            .joined(separator: "\n")

        share(combined, filename: "sleepypod-\(side)-\(Date().ISO8601Format().prefix(10)).csv")
    }

    private func share(_ content: String, filename: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        exportURL = url
        showShareSheet = true
    }
}
