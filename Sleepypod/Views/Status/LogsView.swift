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
    @State private var selectedPriority: String? = nil
    @State private var isLoading = false
    @State private var error: String?

    private let services = [
        ("sleepypod", "Core"),
        ("sleepypod-piezo-processor", "Piezo"),
        ("sleepypod-sleep-detector", "Sleep")
    ]

    private let priorities: [(String?, String)] = [
        (nil, "All"),
        ("err", "Errors"),
        ("warning", "Warn"),
        ("debug", "Debug")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filters row
                HStack(spacing: 10) {
                    // Service menu
                    Menu {
                        ForEach(services, id: \.0) { id, label in
                            Button {
                                Haptics.tap()
                                selectedService = id
                                Task { await fetchLogs() }
                            } label: {
                                HStack {
                                    Text(label)
                                    if selectedService == id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 10))
                            Text(services.first { $0.0 == selectedService }?.1 ?? "Core")
                                .font(.caption.weight(.medium))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.cooling)
                        .clipShape(Capsule())
                    }

                    // Priority menu
                    Menu {
                        ForEach(priorities, id: \.1) { value, label in
                            Button {
                                Haptics.tap()
                                selectedPriority = value
                                Task { await fetchLogs() }
                            } label: {
                                HStack {
                                    Text(label)
                                    if selectedPriority == value { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 10))
                            Text(priorities.first { $0.0 == selectedPriority }?.1 ?? "All")
                                .font(.caption.weight(.medium))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.cardElevated)
                        .clipShape(Capsule())
                    }

                    Spacer()

                    Text("\(logs.count) entries")
                        .font(.caption2)
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.horizontal, 16)
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
            Circle()
                .fill(entry.levelColor)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.message)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .textSelection(.enabled)

                // Pretty-printed JSON payload if present
                if let json = entry.jsonPayload {
                    Text(json)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.accent.opacity(0.7))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "0f0f1a"))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .textSelection(.enabled)
                }

                HStack(spacing: 6) {
                    Text(entry.time)
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textMuted)
                    if let tag = entry.levelTag {
                        Text(tag)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(entry.levelColor)
                    }
                }
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
        var params = "\"unit\":\"\(unit)\",\"lines\":200"
        if let priority = selectedPriority {
            params += ",\"priority\":\"\(priority)\""
        }
        let input = "{\"json\":{\(params)}}"
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
    let jsonPayload: String?
    let levelTag: String?

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

    static func parse(_ line: String, index: Int) -> LogEntry {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Extract timestamp
        var time = ""
        var rest = trimmed

        if trimmed.count > 19, trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)] == "-" {
            let tsEnd = trimmed.index(trimmed.startIndex, offsetBy: min(19, trimmed.count))
            let ts = String(trimmed[..<tsEnd])
            if let tIdx = ts.firstIndex(of: "T") {
                time = String(ts[ts.index(after: tIdx)...])
            } else {
                time = ts
            }
            if let colonIdx = trimmed[tsEnd...].firstIndex(of: ":") {
                rest = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            }
        }

        // Detect level
        let lower = rest.lowercased()
        let level: Level
        let tag: String?
        if lower.contains("[error]") || lower.contains("error:") {
            level = .error; tag = "ERROR"
        } else if lower.contains("[warn]") || lower.contains("warning:") {
            level = .warn; tag = "WARN"
        } else if lower.contains("[debug]") {
            level = .debug; tag = "DEBUG"
        } else {
            level = .info; tag = nil
        }

        // Clean level tags
        var msg = rest
            .replacingOccurrences(of: "[INFO] ", with: "")
            .replacingOccurrences(of: "[WARN] ", with: "")
            .replacingOccurrences(of: "[ERROR] ", with: "")
            .replacingOccurrences(of: "[DEBUG] ", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Extract and prettify JSON
        var jsonPayload: String?
        if let jsonStart = msg.firstIndex(of: "{"),
           let jsonData = String(msg[jsonStart...]).data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: jsonData),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let prettyStr = String(data: pretty, encoding: .utf8) {
            jsonPayload = prettyStr
            msg = String(msg[..<jsonStart]).trimmingCharacters(in: .whitespaces)
            // Clean trailing punctuation
            if msg.hasSuffix(":") || msg.hasSuffix("-") {
                msg = String(msg.dropLast()).trimmingCharacters(in: .whitespaces)
            }
        }

        if msg.isEmpty { msg = trimmed }

        return LogEntry(id: index, time: time, level: level, message: msg, jsonPayload: jsonPayload, levelTag: tag)
    }
}
