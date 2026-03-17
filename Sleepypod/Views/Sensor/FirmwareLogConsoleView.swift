import SwiftUI

/// Terminal-style auto-scrolling console showing live firmware log messages.
struct FirmwareLogConsoleView: View {
    let logs: [FirmwareLogEntry]
    var onClear: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.caption)
                    .foregroundColor(Theme.healthy)
                Text("FIRMWARE CONSOLE")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
                Spacer()
                Text("\(logs.count) lines")
                    .font(.system(size: 9).monospaced())
                    .foregroundColor(Theme.textMuted)
                Button {
                    Haptics.light()
                    onClear()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textMuted)
                }
                .buttonStyle(.plain)
            }

            // Log view
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logs) { entry in
                            logRow(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: logs.count) {
                    if let last = logs.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(height: 180)
            .background(Color(hex: "0a0a10"))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "1a1a2e"), lineWidth: 1)
            )
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }

    private func logRow(_ entry: FirmwareLogEntry) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Timestamp
            Text(timeString(entry.timestamp))
                .foregroundColor(Theme.textMuted)
                .frame(width: 55, alignment: .leading)

            // Level badge
            Text(entry.level.rawValue.prefix(3).uppercased())
                .foregroundColor(entry.level.color)
                .frame(width: 30, alignment: .leading)

            Text(cleanMessage(entry.message))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(2)
        }
        .font(.system(size: 9, design: .monospaced))
    }

    private static let timeFmt: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt
    }()

    private func timeString(_ date: Date) -> String {
        Self.timeFmt.string(from: date)
    }

    private func cleanMessage(_ msg: String) -> String {
        // Strip common firmware prefixes like "153379934 Sensor.cpp:614 handleCommand|"
        if let pipeIdx = msg.firstIndex(of: "|") {
            return String(msg[msg.index(after: pipeIdx)...]).trimmingCharacters(in: .whitespaces)
        }
        return msg
    }
}
