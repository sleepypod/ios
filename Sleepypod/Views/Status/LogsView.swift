import SwiftUI

struct LogsView: View {
    @Environment(DeviceManager.self) private var deviceManager
    @State private var logFiles: [String] = []
    @State private var selectedFile: String?
    @State private var logContent: String = ""
    @State private var isLoading = false
    @State private var isExpanded = false

    private var baseURL: String {
        guard let ip = UserDefaults.standard.string(forKey: "podIPAddress"), !ip.isEmpty else { return "" }
        return "http://\(ip):3000"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
                if isExpanded && logFiles.isEmpty {
                    Task { await fetchLogFiles() }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.textSecondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Logs")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        Text("View server log files")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .background(Theme.cardBorder)
                    .padding(.vertical, 10)

                if isLoading && logFiles.isEmpty {
                    HStack {
                        ProgressView().tint(Theme.accent)
                        Text("Loading log files…")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.bottom, 8)
                } else if logFiles.isEmpty {
                    Text("No log files found")
                        .font(.caption)
                        .foregroundColor(Theme.textMuted)
                        .padding(.bottom, 8)
                } else {
                    // File picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(logFiles, id: \.self) { file in
                                Button {
                                    Haptics.tap()
                                    selectedFile = file
                                    Task { await fetchLog(file) }
                                } label: {
                                    Text(file)
                                        .font(.caption)
                                        .foregroundColor(selectedFile == file ? .white : Theme.textSecondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(selectedFile == file ? Theme.cooling : Theme.cardElevated)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.bottom, 8)

                    // Log content
                    if isLoading && selectedFile != nil {
                        HStack {
                            ProgressView().tint(Theme.accent)
                            Text("Loading…")
                                .font(.caption)
                                .foregroundColor(Theme.textMuted)
                        }
                    } else if !logContent.isEmpty {
                        ScrollView {
                            Text(logContent)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 300)
                        .padding(8)
                        .background(Color(hex: "0f0f0f"))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func fetchLogFiles() async {
        guard !baseURL.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "\(baseURL)/api/logs") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try JSONDecoder().decode(LogFilesResponse.self, from: data)
            logFiles = result.logs
        } catch {
            // Silently fail
        }
    }

    private func fetchLog(_ filename: String) async {
        guard !baseURL.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        // The SSE endpoint returns data: { message: "..." } — fetch as regular GET with short timeout
        guard let url = URL(string: "\(baseURL)/api/logs/\(filename)") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let text = String(data: data, encoding: .utf8) ?? ""
            // Parse SSE: "data: {...}\n\n"
            if let jsonStart = text.firstIndex(of: "{"),
               let jsonData = text[jsonStart...].data(using: .utf8),
               let parsed = try? JSONDecoder().decode(LogMessage.self, from: jsonData) {
                logContent = parsed.message
            } else {
                logContent = text
            }
        } catch {
            logContent = "Failed to load log"
        }
    }
}

private struct LogFilesResponse: Decodable {
    let logs: [String]
}

private struct LogMessage: Decodable {
    let message: String
}
