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
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct WeekPickerSheet: View {
    @Environment(MetricsManager.self) private var metricsManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker(
                    "Select week",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(Theme.accent)
                .padding(.horizontal)

                Button {
                    Haptics.medium()
                    metricsManager.selectedWeekStart = Calendar.current.startOfWeek(for: selectedDate)
                    Task { await metricsManager.fetchAll() }
                    dismiss()
                } label: {
                    Text("Show This Week")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
            .background(Theme.background)
            .navigationTitle("Select Date Range")
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
