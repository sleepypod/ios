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

    private let api: SleepypodProtocol

    init(api: SleepypodProtocol) {
        self.api = api
    }

    // MARK: - Current Schedule

    var currentDailySchedule: DailySchedule? {
        guard let schedules else { return nil }
        let sideSchedule = schedules.schedule(for: selectedSide.primarySide)
        return sideSchedule[selectedDay]
    }

    var phases: [SchedulePhase] {
        guard let daily = currentDailySchedule else { return [] }
        let sorted = daily.temperatures.sorted { time1, time2 in
            time1.key < time2.key
        }

        let phaseNames = ["Bedtime", "Deep Sleep", "Pre-Wake", "Wake Up"]
        let phaseIcons = ["moon.fill", "moon.zzz.fill", "sunrise.fill", "sun.max.fill"]

        return sorted.enumerated().map { index, entry in
            let name = index < phaseNames.count ? phaseNames[index] : "Phase \(index + 1)"
            let icon = index < phaseIcons.count ? phaseIcons[index] : "clock.fill"
            return SchedulePhase(name: name, icon: icon, time: entry.key, temperatureF: entry.value)
        }
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
        guard var schedules else { return }
        let side = selectedSide.primarySide
        var sideSchedule = schedules.schedule(for: side)
        var daily = sideSchedule[selectedDay]

        let temps = daily.temperatures.keys.sorted()
        let profileTemps = profile.temperatures(for: temps.count)

        for (index, time) in temps.enumerated() {
            daily.temperatures[time] = profileTemps[index]
        }

        sideSchedule[selectedDay] = daily
        schedules.setSchedule(sideSchedule, for: side)
        self.schedules = schedules

        do {
            self.schedules = try await api.updateSchedules(schedules, days: [selectedDay])
        } catch {
            self.error = error.localizedDescription
            await fetchSchedules()
        }
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
