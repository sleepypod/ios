import SwiftUI

/// Unified diagnostic console — firmware logs (default) + raw frame inspector.
/// Terminal-style with auto-scroll, pause, type filtering.
struct FirmwareLogConsoleView: View {
    let logs: [FirmwareLogEntry]
    let recentFrames: [RawFrameEntry]
    var onClear: () -> Void = {}

    @State private var mode: ConsoleMode = .logs
    @State private var paused = false
    @State private var selectedFrame: RawFrameEntry?
    @State private var typeFilter: String?

    enum ConsoleMode: String, CaseIterable {
        case logs = "Logs"
        case frames = "Frames"
    }

    private static let typeColors: [String: Color] = [
        "piezo-dual": Color(hex: "a78bfa"),
        "capSense2": Color(hex: "4ade80"),
        "bedTemp2": Color(hex: "fb923c"),
        "frzHealth": Color(hex: "60a5fa"),
        "frzTemp": Color(hex: "60a5fa"),
        "deviceStatus": Color(hex: "38bdf8"),
        "log": Color(hex: "fbbf24"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.caption)
                    .foregroundColor(Theme.healthy)
                Text("CONSOLE")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
                    .tracking(1)
                Spacer()

                // Mode toggle
                Picker("Mode", selection: $mode) {
                    ForEach(ConsoleMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                // Pause
                Button {
                    Haptics.light()
                    paused.toggle()
                } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 10))
                        .foregroundColor(paused ? Theme.amber : Theme.textMuted)
                }
                .buttonStyle(.plain)

                // Count
                Text("\(mode == .logs ? logs.count : filteredFrames.count)")
                    .font(.system(size: 9).monospaced())
                    .foregroundColor(Theme.textMuted)

                // Clear
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

            // Type filter (frames mode)
            if mode == .frames {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        FilterPill(label: "All", active: typeFilter == nil) { typeFilter = nil }
                        ForEach(seenTypes, id: \.self) { type in
                            FilterPill(label: type, active: typeFilter == type) { typeFilter = type }
                        }
                    }
                }
            }

            // Console body
            Group {
                if mode == .logs {
                    logsView
                } else {
                    framesView
                }
            }
            .frame(height: 200)
            .background(Color(hex: "0a0a10"))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "1a1a2e"), lineWidth: 1)
            )
        }
        .cardStyle()
    }

    // MARK: - Logs View

    private var logsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(logs) { entry in
                        logRow(entry).id(entry.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: logs.count) {
                if !paused, let last = logs.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Frames View

    private var filteredFrames: [RawFrameEntry] {
        let src = recentFrames
        if let filter = typeFilter {
            return Array(src.filter { $0.type == filter }.prefix(100))
        }
        return Array(src.prefix(100))
    }

    private var seenTypes: [String] {
        Array(Set(recentFrames.map(\.type))).sorted()
    }

    private var framesView: some View {
        HStack(spacing: 0) {
            // Frame list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredFrames) { frame in
                        Button {
                            if selectedFrame?.id == frame.id {
                                selectedFrame = nil
                            } else {
                                selectedFrame = frame
                                if !paused { paused = true }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(Self.timeFmt.string(from: frame.timestamp))
                                    .foregroundColor(Theme.textMuted)
                                Text(frame.type)
                                    .foregroundColor(Self.typeColors[frame.type] ?? Theme.accent)
                                    .fontWeight(.medium)
                                Spacer()
                                let age = Date.now.timeIntervalSince(frame.timestamp)
                                Text(String(format: "%.1fs", age))
                                    .foregroundColor(Theme.textMuted.opacity(0.5))
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(selectedFrame?.id == frame.id ? Theme.accent.opacity(0.1) : .clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: selectedFrame != nil ? 140 : .infinity)

            // Detail panel
            if let frame = selectedFrame {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(frame.type)
                                .foregroundColor(Self.typeColors[frame.type] ?? Theme.accent)
                                .fontWeight(.medium)
                            Text(Self.timeFmt.string(from: frame.timestamp))
                                .foregroundColor(Theme.textMuted)
                        }
                        .font(.system(size: 10, design: .monospaced))

                        // Pretty-print JSON
                        Text(prettyJSON(frame.json))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .textSelection(.enabled)
                    }
                    .padding(8)
                }
            }
        }
    }

    // MARK: - Helpers

    private func logRow(_ entry: FirmwareLogEntry) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(Self.timeFmt.string(from: entry.timestamp))
                .foregroundColor(Theme.textMuted)
                .frame(width: 55, alignment: .leading)
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

    private func cleanMessage(_ msg: String) -> String {
        if let pipeIdx = msg.firstIndex(of: "|") {
            return String(msg[msg.index(after: pipeIdx)...]).trimmingCharacters(in: .whitespaces)
        }
        return msg
    }

    private func prettyJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8)
        else { return json }
        return str
    }
}

// MARK: - Filter Pill

private struct FilterPill: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(active ? Theme.accent : Theme.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? Theme.accent.opacity(0.15) : Color(hex: "1a1a2e"))
                )
        }
        .buttonStyle(.plain)
    }
}
