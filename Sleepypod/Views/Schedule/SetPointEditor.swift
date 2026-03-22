import SwiftUI

// MARK: - Data Model

struct SetPoint: Identifiable, Equatable {
    let id: UUID
    var time: String    // "HH:mm" 24-hour format
    var tempF: Int      // 55-110
    var phase: String   // "Warm-up", "Cool-down", "Deep Sleep", "Maintain", "Pre-Wake", "Wake"

    init(id: UUID = UUID(), time: String, tempF: Int, phase: String) {
        self.id = id
        self.time = time
        self.tempF = tempF
        self.phase = phase
    }
}

// MARK: - SetPointEditor

struct SetPointEditor: View {
    @Binding var points: [SetPoint]
    var temperatureFormat: TemperatureFormat
    var onChanged: (() -> Void)?

    @State private var expandedTimeID: UUID?
    @State private var editMode: EditMode = .inactive

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Set Points")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    Haptics.light()
                    addPoint()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Rows
            let sorted = points.sorted { overnightSort($0.time, $1.time) }
            ForEach(sorted) { point in
                VStack(spacing: 0) {
                    setPointRow(point: point)

                    // Inline time picker when expanded
                    if expandedTimeID == point.id {
                        timePicker(for: point)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .onDelete { offsets in
                guard points.count > 3 else { return }
                var sorted = points.sorted { overnightSort($0.time, $1.time) }
                sorted.remove(atOffsets: offsets)
                points = sorted
                onChanged?()
            }
        }
    }

    // MARK: - Row

    private func setPointRow(point: SetPoint) -> some View {
        HStack(spacing: 10) {
            // Phase dot
            Circle()
                .fill(phaseColor(point.phase))
                .frame(width: 8, height: 8)

            // Phase label
            Text(point.phase)
                .font(.system(size: 9))
                .foregroundColor(Theme.textMuted)
                .frame(width: 60, alignment: .leading)
                .lineLimit(1)

            // Tappable time
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedTimeID = expandedTimeID == point.id ? nil : point.id
                }
            } label: {
                Text(point.time)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        expandedTimeID == point.id
                            ? Theme.accent.opacity(0.15)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Spacer()

            // Temperature stepper
            HStack(spacing: 8) {
                Button {
                    Haptics.light()
                    updateTemp(id: point.id, delta: -1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Theme.cardElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Text(TemperatureConversion.displayTemp(point.tempF, format: temperatureFormat))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(TempColor.forOffset(point.tempF - 80))
                    .frame(minWidth: 48)

                Button {
                    Haptics.light()
                    updateTemp(id: point.id, delta: 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Theme.cardElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Delete button
            if points.count > 3 {
                Button {
                    Haptics.light()
                    deletePoint(id: point.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.error.opacity(0.7))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Inline Time Picker

    private func timePicker(for point: SetPoint) -> some View {
        let binding = Binding<Date>(
            get: {
                dateFromTimeString(point.time) ?? Date()
            },
            set: { newDate in
                updateTime(id: point.id, date: newDate)
            }
        )

        return DatePicker(
            "",
            selection: binding,
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(height: 120)
        .clipped()
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func updateTemp(id: UUID, delta: Int) {
        if let index = points.firstIndex(where: { $0.id == id }) {
            let newTemp = max(55, min(110, points[index].tempF + delta))
            points[index].tempF = newTemp
            onChanged?()
        }
    }

    private func updateTime(id: UUID, date: Date) {
        if let index = points.firstIndex(where: { $0.id == id }) {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            points[index].time = fmt.string(from: date)
            // Auto-sort after time change
            points.sort { overnightSort($0.time, $1.time) }
            onChanged?()
        }
    }

    private func deletePoint(id: UUID) {
        guard points.count > 3 else { return }
        points.removeAll { $0.id == id }
        onChanged?()
    }

    private func addPoint() {
        let sorted = points.sorted { overnightSort($0.time, $1.time) }
        let midIndex = sorted.count / 2
        let refTime = sorted.indices.contains(midIndex) ? sorted[midIndex].time : "02:00"
        let refTemp = sorted.indices.contains(midIndex) ? sorted[midIndex].tempF : 74

        let newTime = nudgeTime(refTime, by: 15)
        let newPoint = SetPoint(time: newTime, tempF: refTemp, phase: "Maintain")
        points.append(newPoint)
        points.sort { overnightSort($0.time, $1.time) }
        onChanged?()
    }

    // MARK: - Helpers

    private func nudgeTime(_ time: String, by minutes: Int) -> String {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return time }
        let totalMinutes = (parts[0] * 60 + parts[1] + minutes) % (24 * 60)
        return String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
    }

    private func dateFromTimeString(_ time: String) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = parts[0]
        components.minute = parts[1]
        return Calendar.current.date(from: components)
    }

    /// Overnight-aware time sort: times >= 12:00 (evening) come before times < 12:00 (morning).
    /// This ensures "22:00", "23:30", "01:00", "05:00" sort in overnight order.
    private func overnightSort(_ a: String, _ b: String) -> Bool {
        let aIsEvening = a >= "12:00"
        let bIsEvening = b >= "12:00"
        if aIsEvening == bIsEvening { return a < b }
        return aIsEvening // evenings first
    }

    private func phaseColor(_ phase: String) -> Color {
        let lower = phase.lowercased()
        if lower.contains("warm") && lower.contains("up") { return Theme.warming }
        if lower.contains("cool") { return Theme.cooling }
        if lower.contains("deep") { return Color(hex: "2563eb") }
        if lower.contains("maintain") { return Theme.textSecondary }
        if lower.contains("pre") && lower.contains("wake") { return Theme.amber }
        if lower.contains("wake") { return Theme.textMuted }
        return Theme.textSecondary
    }
}
