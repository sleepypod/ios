import Foundation
import Observation

@MainActor
@Observable
final class MetricsManager {
    var sleepRecords: [SleepRecord] = []
    var vitalsRecords: [VitalsRecord] = []
    var vitalsSummary: VitalsSummary?
    var movementRecords: [MovementRecord] = []
    var selectedSide: Side = .left
    var selectedWeekStart: Date = Calendar.current.startOfWeek(for: Date())
    var isLoading = false
    var error: String?

    private var api: SleepypodProtocol

    init(api: SleepypodProtocol) {
        self.api = api
    }

    func switchBackend(_ client: SleepypodProtocol) { api = client }

    // MARK: - Computed

    var selectedWeekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: selectedWeekStart) ?? selectedWeekStart
    }

    var weekLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: selectedWeekStart)
        let end = formatter.string(from: Calendar.current.date(byAdding: .day, value: 6, to: selectedWeekStart) ?? selectedWeekStart)
        return "\(start) - \(end)"
    }

    var selectedDayRecord: SleepRecord? {
        sleepRecords.first
    }

    var averageSleepHours: Double {
        guard !sleepRecords.isEmpty else { return 0 }
        return sleepRecords.reduce(0.0) { $0 + $1.durationHours } / Double(sleepRecords.count)
    }

    var totalMovement: Int {
        movementRecords.reduce(0) { $0 + $1.totalMovement }
    }

    // MARK: - Navigation

    func previousWeek() {
        selectedWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: selectedWeekStart) ?? selectedWeekStart
        Task { await fetchAll() }
    }

    func nextWeek() {
        let next = Calendar.current.date(byAdding: .day, value: 7, to: selectedWeekStart) ?? selectedWeekStart
        guard next <= Date() else { return }
        selectedWeekStart = next
        Task { await fetchAll() }
    }

    // MARK: - Fetch

    private var requestGeneration = 0

    func fetchAll() async {
        requestGeneration += 1
        let generation = requestGeneration
        let side = selectedSide
        let start = selectedWeekStart
        // Include the morning following the last bedtime in this week.
        let end = selectedWeekEnd.addingTimeInterval(12 * 3600)
        isLoading = true
        error = nil
        do {
            async let sleep = api.getSleepRecords(side: side, start: start, end: end)
            async let vitals = api.getVitals(side: side, start: start, end: end)
            async let movement = api.getMovement(side: side, start: start, end: end)
            async let summary = api.getVitalsSummary(side: side, start: start, end: end)
            let result = try await (sleep, vitals, movement, summary)
            guard generation == requestGeneration, side == selectedSide, start == selectedWeekStart else { return }
            sleepRecords = result.0.filter { $0.side == side.rawValue && $0.enteredBedDate >= start && $0.enteredBedDate < selectedWeekEnd }
                .sorted { $0.enteredBedDate > $1.enteredBedDate }
            vitalsRecords = result.1.filter { $0.side == side.rawValue }
            movementRecords = result.2
            vitalsSummary = result.3
        } catch {
            guard generation == requestGeneration else { return }
            self.error = error.localizedDescription
            sleepRecords = []; vitalsRecords = []; movementRecords = []; vitalsSummary = nil
        }
        if generation == requestGeneration { isLoading = false }
    }

}

// MARK: - Calendar Extension

extension Calendar {
    /// Weeks start on Monday, matching the M–S day chips and week bars.
    func startOfWeek(for date: Date) -> Date {
        var calendar = self
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }
}
