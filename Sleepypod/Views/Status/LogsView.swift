import SwiftUI

struct LogsView: View {
    @State private var logContent: String = ""
    @State private var selectedUnit: String = "sleepypod.service"
    @State private var isLoading = false
    @State private var isExpanded = false
    @State private var error: String?

    private let units = [
        "sleepypod.service",
        "sleepypod-piezo-processor.service",
        "sleepypod-sleep-detector.service"
    ]

    private var api: SleepypodProtocol { APIBackend.current.createClient() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
                if isExpanded && logContent.isEmpty {
                    Task { await fetchLogs() }
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
                        Text("systemd journal")
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

                // Unit picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(units, id: \.self) { unit in
                            Button {
                                Haptics.tap()
                                selectedUnit = unit
                                Task { await fetchLogs() }
                            } label: {
                                Text(unit.replacingOccurrences(of: ".service", with: ""))
                                    .font(.caption2)
                                    .foregroundColor(selectedUnit == unit ? .white : Theme.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selectedUnit == unit ? Theme.cooling : Theme.cardElevated)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.bottom, 8)

                // Log content
                if isLoading {
                    HStack {
                        ProgressView().tint(Theme.accent).scaleEffect(0.7)
                        Text("Loading logs…")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.bottom, 8)
                } else if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Theme.error)
                        .padding(.bottom, 8)
                } else if !logContent.isEmpty {
                    ScrollView {
                        Text(logContent)
                            .font(.system(size: 9, design: .monospaced))
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
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func fetchLogs() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let base = URL(string: "http://\(UserDefaults.standard.string(forKey: "podIPAddress") ?? ""):3000") else {
            error = "No pod IP configured"
            return
        }

        let input = "{\"json\":{\"unit\":\"\(selectedUnit)\",\"lines\":50}}"
        let encoded = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        guard let url = URL(string: "\(base)/api/trpc/system.getLogs?input=\(encoded)") else { return }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)

            // Parse tRPC response: {"result":{"data":{"json":{"lines":["..."]}}}}
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any],
               let dataObj = result["data"] as? [String: Any],
               let jsonObj = dataObj["json"] as? [String: Any],
               let lines = jsonObj["lines"] as? [String] {
                logContent = lines.joined(separator: "\n")
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let errObj = json["error"] as? [String: Any],
                      let errJson = errObj["json"] as? [String: Any],
                      let msg = errJson["message"] as? String {
                error = msg
            } else {
                logContent = String(data: data, encoding: .utf8) ?? "Unable to parse response"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
