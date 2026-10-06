import Foundation
import Observation

@MainActor
@Observable
final class ScheduleManager {
    var schedules: Schedules?
    var selectedDay: DayOfWeek = .monday
    var selectedDays: Set<DayOfWeek> = [.monday]
    var selectedSide: SideSelection = .left
    var isLoading = false
    var error: String?

    private var api: SleepypodProtocol

    init(api: SleepypodProtocol) {
        self.api = api
    }

    func switchBackend(_ client: SleepypodProtocol) { api = client }

    // MARK: - Current Schedule

    var currentDailySchedule: DailySchedule? {
        guard let schedules else { return nil }
        let sideSchedule = schedules.schedule(for: selectedSide.primarySide)
        return sideSchedule[selectedDay]
    }

    var phases: [SchedulePhase] {
        guard let daily = currentDailySchedule else { return [] }
        let sorted = daily.temperatures.sorted { time1, time2 in
            (DisplayTime.minutes(time1.key) - DisplayTime.minutes(daily.power.on) + 1440) % 1440 < (DisplayTime.minutes(time2.key) - DisplayTime.minutes(daily.power.on) + 1440) % 1440
        }

        return sorted.enumerated().map { index, entry in
            let (name, icon) = Self.phaseLabel(index: index, count: sorted.count)
            return SchedulePhase(name: name, icon: icon, time: entry.key, temperatureF: entry.value)
        }
    }

    /// First point is bedtime, the last is pre-wake, and the ones between are the night holds.
    static func phaseLabel(index: Int, count: Int) -> (String, String) {
        if index == 0 { return ("Bedtime", "bed.double") }
        if index == count - 1 && count >= 2 { return ("Pre-wake", "sunrise") }
        switch index {
        case 1: return ("Deep", "moon")
        case 2: return ("Late night", "moon.stars")
        default: return ("Phase \(index + 1)", "moon.stars")
        }
    }

    func applyTemplate(_ template: CurveTemplate) async -> Bool {
        guard var updated = schedules else { return false }
        for side in selectedSide.sides {
            var sideSchedule = updated.schedule(for: side)
            for day in selectedDays {
                var daily = sideSchedule[day]
                daily.temperatures = template.points
                daily.power.on = template.bedtime
                daily.power.off = template.wake
                daily.power.enabled = true
                daily.alarm.time = template.wake
                daily.alarm.enabled = true
                sideSchedule[day] = daily
            }
            updated.setSchedule(sideSchedule, for: side)
        }
        do { schedules = try await api.updateSchedules(updated, days: selectedDays); error = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }

    func editPhase(oldTime: String, newTime: String, temperature: Int) async -> Bool {
        guard var updated = schedules else { return false }
        for side in selectedSide.sides {
            var sideSchedule = updated.schedule(for: side)
            for day in selectedDays {
                var daily = sideSchedule[day]
                if oldTime != newTime && daily.temperatures[newTime] != nil {
                    error = "There is already a set point at that time."
                    return false
                }
                daily.temperatures.removeValue(forKey: oldTime)
                daily.temperatures[newTime] = max(55, min(110, temperature))
                sideSchedule[day] = daily
            }
            updated.setSchedule(sideSchedule, for: side)
        }
        do {
            schedules = try await api.updateSchedules(updated, days: selectedDays)
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    // MARK: - Fetch

    func fetchSchedules() async {
        isLoading = true
        error = nil
        do {
            schedules = try await api.getSchedules()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Toggle Power Schedule

    func togglePowerSchedule() async {
        guard var schedules else { return }
        let side = selectedSide.primarySide
        var sideSchedule = schedules.schedule(for: side)
        var daily = sideSchedule[selectedDay]

        daily.power.enabled.toggle()
        sideSchedule[selectedDay] = daily
        schedules.setSchedule(sideSchedule, for: side)

        if selectedSide == .both {
            var otherSide = schedules.schedule(for: side == .left ? .right : .left)
            var otherDaily = otherSide[selectedDay]
            otherDaily.power.enabled = daily.power.enabled
            otherSide[selectedDay] = otherDaily
            schedules.setSchedule(otherSide, for: side == .left ? .right : .left)
        }

        self.schedules = schedules

        do {
            self.schedules = try await api.updateSchedules(schedules, days: [selectedDay])
        } catch {
            self.error = error.localizedDescription
            await fetchSchedules()
        }
    }

    // MARK: - Update Alarm Time

    func updateAlarmTime(_ time: String) async {
        guard var schedules else { return }
        let side = selectedSide.primarySide
        var sideSchedule = schedules.schedule(for: side)
        var daily = sideSchedule[selectedDay]
        daily.alarm.time = time
        daily.alarm.enabled = true
        sideSchedule[selectedDay] = daily
        schedules.setSchedule(sideSchedule, for: side)

        if selectedSide == .both {
            var other = schedules.schedule(for: side == .left ? .right : .left)
            var otherDaily = other[selectedDay]
            otherDaily.alarm.time = time
            otherDaily.alarm.enabled = true
            other[selectedDay] = otherDaily
            schedules.setSchedule(other, for: side == .left ? .right : .left)
        }

        self.schedules = schedules
        do {
            self.schedules = try await api.updateSchedules(schedules, days: [selectedDay])
        } catch {
            self.error = error.localizedDescription
            await fetchSchedules()
        }
    }

    // MARK: - Update Bedtime

    func updateBedtime(_ time: String) async {
        guard var schedules else { return }
        let side = selectedSide.primarySide
        var sideSchedule = schedules.schedule(for: side)
        var daily = sideSchedule[selectedDay]
        daily.power.on = time
        daily.power.enabled = true
        sideSchedule[selectedDay] = daily
        schedules.setSchedule(sideSchedule, for: side)

        if selectedSide == .both {
            var other = schedules.schedule(for: side == .left ? .right : .left)
            var otherDaily = other[selectedDay]
            otherDaily.power.on = time
            otherDaily.power.enabled = true
            other[selectedDay] = otherDaily
            schedules.setSchedule(other, for: side == .left ? .right : .left)
        }

        self.schedules = schedules
        do {
            self.schedules = try await api.updateSchedules(schedules, days: [selectedDay])
        } catch {
            self.error = error.localizedDescription
            await fetchSchedules()
        }
    }

    // MARK: - Update Temperature

    func updatePhaseTemperature(time: String, delta: Int) async {
        guard var schedules else { return }
        let side = selectedSide.primarySide
        var sideSchedule = schedules.schedule(for: side)
        var daily = sideSchedule[selectedDay]

        guard let currentTemp = daily.temperatures[time] else { return }
        let newTemp = max(TemperatureConversion.minTempF, min(TemperatureConversion.maxTempF, currentTemp + delta * 2))
        daily.temperatures[time] = newTemp
        sideSchedule[selectedDay] = daily
        schedules.setSchedule(sideSchedule, for: side)

        // Apply to both sides if linked
        if selectedSide == .both {
            var otherSide = schedules.schedule(for: side == .left ? .right : .left)
            var otherDaily = otherSide[selectedDay]
            otherDaily.temperatures[time] = newTemp
            otherSide[selectedDay] = otherDaily
            schedules.setSchedule(otherSide, for: side == .left ? .right : .left)
        }

        self.schedules = schedules

        do {
            self.schedules = try await api.updateSchedules(schedules, days: [selectedDay])
        } catch {
            self.error = error.localizedDescription
            await fetchSchedules()
        }
    }

    // MARK: - Update Power Schedule

    func updatePowerSchedule(_ power: PowerSchedule) async {
        guard var schedules else { return }
        let side = selectedSide.primarySide

        for day in selectedDays {
            var sideSchedule = schedules.schedule(for: side)
            var daily = sideSchedule[day]
            daily.power = power
            sideSchedule[day] = daily
            schedules.setSchedule(sideSchedule, for: side)

            if selectedSide == .both {
                var other = schedules.schedule(for: side == .left ? .right : .left)
                var otherDaily = other[day]
                otherDaily.power = power
                other[day] = otherDaily
                schedules.setSchedule(other, for: side == .left ? .right : .left)
            }
        }

        self.schedules = schedules
        do {
            self.schedules = try await api.updateSchedules(schedules, days: selectedDays)
        } catch {
            self.error = error.localizedDescription
            await fetchSchedules()
        }
    }

    // MARK: - Update Alarm Schedule

    func updateAlarmSchedule(_ alarm: AlarmSchedule) async {
        guard var schedules else { return }
        let side = selectedSide.primarySide

        for day in selectedDays {
            var sideSchedule = schedules.schedule(for: side)
            var daily = sideSchedule[day]
            daily.alarm = alarm
            sideSchedule[day] = daily
            schedules.setSchedule(sideSchedule, for: side)

            if selectedSide == .both {
                var other = schedules.schedule(for: side == .left ? .right : .left)
                var otherDaily = other[day]
                otherDaily.alarm = alarm
                other[day] = otherDaily
                schedules.setSchedule(other, for: side == .left ? .right : .left)
            }
        }

        self.schedules = schedules
        do {
            self.schedules = try await api.updateSchedules(schedules, days: selectedDays)
        } catch {
            self.error = error.localizedDescription
            await fetchSchedules()
        }
    }

    // MARK: - Profile Presets

    func applyProfile(_ profile: SleepProfile) async {
        guard var updated = schedules else { return }
        for side in selectedSide.sides {
            var sideSchedule = updated.schedule(for: side)
            for day in selectedDays {
                var daily = sideSchedule[day]
                let bedtime = DisplayTime.minutes(daily.power.on)
                let times = daily.temperatures.keys.sorted {
                    (DisplayTime.minutes($0) - bedtime + 1440) % 1440 < (DisplayTime.minutes($1) - bedtime + 1440) % 1440
                }
                let temperatures = profile.temperatures(for: times.count)
                for (index, time) in times.enumerated() { daily.temperatures[time] = temperatures[index] }
                sideSchedule[day] = daily
            }
            updated.setSchedule(sideSchedule, for: side)
        }
        do {
            schedules = try await api.updateSchedules(updated, days: selectedDays)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

}

// MARK: - Sleep Profiles

enum SleepProfile: String, CaseIterable, Identifiable, Sendable {
    case cool = "Cool"
    case balanced = "Balanced"
    case warm = "Warm"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .cool: return "Extra cool all night"
        case .balanced: return "Science-backed curve"
        case .warm: return "Warmer temperatures"
        }
    }

    func temperatures(for count: Int) -> [Int] {
        switch self {
        case .cool:
            switch count {
            case 4: return [72, 66, 66, 70]
            case 3: return [72, 66, 70]
            default: return Array(repeating: 68, count: count)
            }
        case .balanced:
            switch count {
            case 4: return [78, 74, 74, 78]
            case 3: return [78, 74, 78]
            default: return Array(repeating: 76, count: count)
            }
        case .warm:
            switch count {
            case 4: return [84, 80, 80, 84]
            case 3: return [84, 80, 84]
            default: return Array(repeating: 82, count: count)
            }
        }
    }
}
