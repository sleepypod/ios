import Foundation

enum NightPhaseKey: String, Codable, Sendable, CaseIterable {
    case night, dawn
    var title: String { rawValue.capitalized }
}

/// One Night/Dawn phase of tonight's schedule (`schedules.getNightPhases` on sleepypod-core).
struct NightPhase: Codable, Sendable, Equatable {
    /// Time-weighted mean of the phase's set points, °F.
    let temperatureF: Double
    let start: String
    let end: String
    let minutes: Double
    let times: [String]
}

struct NightPhases: Codable, Sendable, Equatable {
    /// No schedule tonight: values preview the balanced template and the first edit writes it.
    let draft: Bool
    let day: DayOfWeek
    /// Days sharing tonight's curve; edits apply to all of them.
    let days: [DayOfWeek]
    let night: NightPhase
    let dawn: NightPhase?

    func phase(_ key: NightPhaseKey) -> NightPhase? { key == .night ? night : dawn }

    /// "Daily", "Weekdays", "Weekends", or runs like "Mon–Wed, Sat" (matches the web stepper).
    var daysSummary: String {
        let set = Set(days)
        let weekdays: [DayOfWeek] = [.monday, .tuesday, .wednesday, .thursday, .friday]
        if set.count == 7 { return "Daily" }
        if set.count == 5 && weekdays.allSatisfy(set.contains) { return "Weekdays" }
        if set.count == 2 && set.contains(.saturday) && set.contains(.sunday) { return "Weekends" }
        var runs: [[DayOfWeek]] = []
        for (index, day) in DayOfWeek.weekdays.enumerated() where set.contains(day) {
            if index > 0 && set.contains(DayOfWeek.weekdays[index - 1]) { runs[runs.count - 1].append(day) } else { runs.append([day]) }
        }
        if runs.count > 1, let first = runs.first, let last = runs.last,
           first.first == .monday, last.last == .sunday, first.count + last.count >= 3 {
            runs = [last + first] + runs.dropFirst().dropLast()
        }
        return runs.map { run in
            run.count >= 3 ? "\(run[0].shortName)–\(run[run.count - 1].shortName)" : run.map(\.shortName).joined(separator: ", ")
        }.joined(separator: ", ")
    }
}

extension DayOfWeek {
    var shortName: String { String(rawValue.prefix(3)).capitalized }
}
