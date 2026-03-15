import SwiftUI

struct LogsView: View {
    @State private var showSheet = false

    var body: some View {
        Button {
            Haptics.light()
            showSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.textSecondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("System Logs")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                    Text("View service activity")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Theme.textMuted)
            }
            .padding(16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            LogsSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Logs Sheet

private struct LogsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logs: [LogEntry] = []
    @State private var selectedService: String = "sleepypod"
    @State private var isLoading = false
    @State private var error: String?

    private let services = [
        ("sleepypod", "Core"),
        ("sleepypod-piezo-processor", "Piezo"),
        ("sleepypod-sleep-detector", "Sleep")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Service picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(services, id: \.0) { id, label in
                            Button {
                                Haptics.tap()
                                selectedService = id
                                Task { await fetchLogs() }
                            } label: {
                                Text(label)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(selectedService == id ? .white : Theme.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(selectedService == id ? Theme.cooling : Theme.cardElevated)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 10)

                Divider().background(Theme.cardBorder)

                // Log entries
                if isLoading {
                    Spacer()
                    ProgressView().tint(Theme.accent)
                    Spacer()
                } else if let error {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundColor(Theme.amber)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    Spacer()
                } else if logs.isEmpty {
                    Spacer()
                    Text("No log entries")
                        .font(.subheadline)
                        .foregroundColor(Theme.textMuted)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(logs) { entry in
                                logRow(entry)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.light()
                        Task { await fetchLogs() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(Theme.accent)
                    }
                }
            }
            .task { await fetchLogs() }
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Level indicator
            Circle()
                .fill(entry.levelColor)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.message)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .textSelection(.enabled)

                Text(entry.time)
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textMuted)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Fetch

    private func fetchLogs() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let ip = UserDefaults.standard.string(forKey: "podIPAddress"), !ip.isEmpty else {
            error = "No Sleepypod connected"
            return
        }

        let unit = "\(selectedService).service"
        let input = "{\"json\":{\"unit\":\"\(unit)\",\"lines\":100}}"
        let encoded = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        guard let url = URL(string: "http://\(ip):3000/api/trpc/system.getLogs?input=\(encoded)") else { return }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let dataObj = result["data"] as? [String: Any],
               let jsonObj = dataObj["json"] as? [String: Any],
               let lines = jsonObj["lines"] as? [String] {
                logs = lines.enumerated().map { i, line in
                    LogEntry.parse(line, index: i)
                }
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let errObj = json["error"] as? [String: Any],
                      let errJson = errObj["json"] as? [String: Any],
                      let msg = errJson["message"] as? String {
                error = msg
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Log Entry

private struct LogEntry: Identifiable {
    let id: Int
    let time: String
    let level: Level
    let message: String

    enum Level {
        case info, warn, error, debug

        var color: Color {
            switch self {
            case .info: Theme.healthy
            case .warn: Theme.amber
            case .error: Theme.error
            case .debug: Theme.textMuted
            }
        }
    }

    var levelColor: Color { level.color }

    /// Parse a journalctl line like:
    /// "2026-03-15T14:30:00+0000 sleepypod[123]: [INFO] Server started on port 3000"
    static func parse(_ line: String, index: Int) -> LogEntry {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Try to extract timestamp from start
        var time = ""
        var rest = trimmed

        // ISO timestamp prefix
        if trimmed.count > 19, trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)] == "-" {
            let tsEnd = trimmed.index(trimmed.startIndex, offsetBy: min(19, trimmed.count))
            let ts = String(trimmed[..<tsEnd])
            // Format to just time
            if let tIdx = ts.firstIndex(of: "T") {
                time = String(ts[ts.index(after: tIdx)...])
            } else {
                time = ts
            }
            // Find message after unit name
            if let colonIdx = trimmed[tsEnd...].firstIndex(of: ":") {
                rest = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            }
        }

        // Detect level
        let level: Level
        let lower = rest.lowercased()
        if lower.contains("[error]") || lower.contains("error:") || lower.contains("err ") {
            level = .error
        } else if lower.contains("[warn]") || lower.contains("warning:") {
            level = .warn
        } else if lower.contains("[debug]") || lower.contains("debug:") {
            level = .debug
        } else {
            level = .info
        }

        // Clean up level tags from message
        var msg = rest
            .replacingOccurrences(of: "[INFO]", with: "")
            .replacingOccurrences(of: "[WARN]", with: "")
            .replacingOccurrences(of: "[ERROR]", with: "")
            .replacingOccurrences(of: "[DEBUG]", with: "")
            .trimmingCharacters(in: .whitespaces)

        if msg.isEmpty { msg = trimmed }

        return LogEntry(id: index, time: time, level: level, message: msg)
    }
}
