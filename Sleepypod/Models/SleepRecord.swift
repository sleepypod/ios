import Foundation

struct SleepRecord: Codable, Sendable, Identifiable {
    var id: Int
    var side: String
    var enteredBedAt: Int       // Unix timestamp
    var leftBedAt: Int          // Unix timestamp
    var sleepPeriodSeconds: Int
    var timesExitedBed: Int
    var presentIntervals: String      // JSON string
    var notPresentIntervals: String   // JSON string

    enum CodingKeys: String, CodingKey {
        case id
        case side
        case enteredBedAt = "entered_bed_at"
        case leftBedAt = "left_bed_at"
        case sleepPeriodSeconds = "sleep_period_seconds"
        case timesExitedBed = "times_exited_bed"
        case presentIntervals = "present_intervals"
        case notPresentIntervals = "not_present_intervals"
    }

    var enteredBedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(enteredBedAt))
    }

    var leftBedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(leftBedAt))
    }

    var durationHours: Double {
        Double(sleepPeriodSeconds) / 3600.0
    }

    var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: enteredBedDate)
    }

    var bedtimeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: enteredBedDate)
    }

    var wakeTimeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: leftBedDate)
    }

    var durationFormatted: String {
        let hours = sleepPeriodSeconds / 3600
        let minutes = (sleepPeriodSeconds % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}
