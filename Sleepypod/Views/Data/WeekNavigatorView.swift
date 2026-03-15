import SwiftUI

struct WeekNavigatorView: View {
    @Environment(MetricsManager.self) private var metricsManager
    @State private var showDatePicker = false

    var body: some View {
        Button {
            Haptics.light()
            showDatePicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.accent)
                Text(metricsManager.weekLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDatePicker) {
            WeekPickerSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct WeekPickerSheet: View {
    @Environment(MetricsManager.self) private var metricsManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date = Date()

    private var weekStart: Date {
        Calendar.current.startOfWeek(for: selectedDate)
    }

    private var weekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
    }

    private var weekRangeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: weekStart)) - \(fmt.string(from: weekEnd))"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Selected range display
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected Week")
                            .font(.caption)
                            .foregroundColor(Theme.textMuted)
                        Text(weekRangeLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.accent.opacity(0.08))

                DatePicker(
                    "Select date",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(Theme.accent)
                .padding(.horizontal, 8)

                // Confirm button
                Button {
                    Haptics.medium()
                    metricsManager.selectedWeekStart = weekStart
                    Task { await metricsManager.fetchAll() }
                    dismiss()
                } label: {
                    Text("Show \(weekRangeLabel)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Theme.background)
            .navigationTitle("Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.textMuted)
                }
            }
            .onAppear {
                selectedDate = metricsManager.selectedWeekStart
            }
        }
    }
}
