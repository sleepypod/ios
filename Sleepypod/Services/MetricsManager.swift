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

    private let api: SleepypodProtocol

    init(api: SleepypodProtocol) {
        self.api = api
    }

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

    func fetchAll() async {
        isLoading = true
        error = nil
        let start = selectedWeekStart
        let end = selectedWeekEnd

        async let sleepTask: () = fetchSleep(start: start, end: end)
        async let vitalsTask: () = fetchVitals(start: start, end: end)
        async let movementTask: () = fetchMovement(start: start, end: end)
        async let summaryTask: () = fetchVitalsSummary(start: start, end: end)

        _ = await (sleepTask, vitalsTask, movementTask, summaryTask)
        isLoading = false
    }

    private func fetchSleep(start: Date, end: Date) async {
        do {
            sleepRecords = try await api.getSleepRecords(side: selectedSide, start: start, end: end)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchVitals(start: Date, end: Date) async {
        do {
            vitalsRecords = try await api.getVitals(side: selectedSide, start: start, end: end)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchVitalsSummary(start: Date, end: Date) async {
        do {
            vitalsSummary = try await api.getVitalsSummary(side: selectedSide, start: start, end: end)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchMovement(start: Date, end: Date) async {
        do {
            movementRecords = try await api.getMovement(side: selectedSide, start: start, end: end)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Calendar Extension

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}
