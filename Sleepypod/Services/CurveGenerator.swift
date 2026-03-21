import Foundation

/// Generates temperature curves from natural language descriptions.
/// Builds a prompt template for external AI services (ChatGPT, Claude, Gemini, etc.)
/// and parses the structured JSON response.
@MainActor
@Observable
final class CurveGenerator {
    var isGenerating = false
    var error: String?
    var lastResult: GeneratedCurve?

    struct GeneratedCurve: Sendable {
        let bedtime: String      // "HH:mm"
        let wake: String         // "HH:mm"
        let points: [String: Int] // "HH:mm" -> tempF
        let reasoning: String
        let profileName: String
    }

    // MARK: - Prompt Generation

    /// Build a prompt template incorporating the user's sleep preferences.
    /// The user copies this prompt into any external AI assistant.
    func generatePrompt(preferences: String) -> String {
        isGenerating = true
        defer { isGenerating = false }

        let prompt = """
        You are a board-certified sleep medicine physician with expertise in \
        thermoregulation and circadian biology. Based on the user's sleep \
        preferences below, generate an optimal nightly temperature curve for \
        a water-based bed temperature control system.

        **System capabilities:**
        - Water temperature range: 55\u{00B0}F to 110\u{00B0}F
        - Neutral (body-neutral) temperature: ~82.5\u{00B0}F
        - Typical comfortable sleep range: 65\u{00B0}F to 90\u{00B0}F

        **Sleep science context:**
        - Cooling the body before sleep promotes deep sleep onset \
        (Heller & Grahn, Stanford)
        - Core body temperature drops ~2\u{00B0}F by 3 AM at the circadian nadir \
        (Kr\u{00E4}uchi, University of Basel)
        - Gradual warming before wake supports the cortisol awakening response \
        (Czeisler, Harvard Division of Sleep Medicine)
        - Growth hormone release peaks during deep sleep in cooler conditions
        - The system heats/cools water in tubing \u{2014} changes take ~15\u{2013}20 min \
        to stabilize

        **Individual variation guidance:**
        Consider the user's thermal phenotype (hot sleeper vs cold sleeper), \
        chronotype (early bird vs night owl), and any mentioned conditions \
        (e.g., menopause, chronic pain, post-exercise recovery). Adjust the \
        curve aggressiveness and temperature floor/ceiling accordingly.

        **User's sleep preferences:**
        \(preferences)

        **Instructions:**
        - Generate 8\u{2013}15 temperature set points spanning from bedtime minus \
        45 minutes through wake plus 30 minutes
        - Include a warm-up phase before bed, a cooling ramp after bedtime, \
        a deep-sleep cold hold, a gradual pre-wake warming, and a post-wake \
        return to neutral
        - All temperatures must be integers between 55 and 110 (\u{00B0}F)
        - Times must be in 24-hour "HH:mm" format

        Respond ONLY with the following JSON object, no other text:
        {
          "name": "Short title (2-3 words max, e.g. Deep Cool, Gentle Warm, Athletic Recovery)",
          "bedtime": "HH:mm",
          "wake": "HH:mm",
          "points": {
            "HH:mm": temperatureF,
            "HH:mm": temperatureF
          },
          "reasoning": "Brief explanation of the curve design choices"
        }

        IMPORTANT: The "name" field must be 2-3 words maximum. It is used as a label in the UI.
        """

        return prompt
    }

    // MARK: - JSON Parsing

    /// Parse the AI's JSON response into a GeneratedCurve.
    /// Handles common formatting issues (markdown code fences, extra whitespace).
    func parse(json: String) -> GeneratedCurve? {
        error = nil

        // Strip markdown code fences if present
        var cleaned = json
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract JSON object if there's surrounding text
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[start...end])
        }

        guard let data = cleaned.data(using: .utf8),
              let curveJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            error = "Could not parse JSON. Make sure you pasted the complete AI response."
            return nil
        }

        guard let bedtime = curveJSON["bedtime"] as? String else {
            error = "Missing \"bedtime\" field in response."
            return nil
        }
        guard let wake = curveJSON["wake"] as? String else {
            error = "Missing \"wake\" field in response."
            return nil
        }
        guard let pointsRaw = curveJSON["points"] as? [String: Any] else {
            error = "Missing \"points\" field in response."
            return nil
        }

        // Validate time format
        let timeRegex = /^\d{2}:\d{2}$/
        guard bedtime.wholeMatch(of: timeRegex) != nil,
              wake.wholeMatch(of: timeRegex) != nil else {
            error = "Bedtime and wake must be in HH:mm format."
            return nil
        }

        var points: [String: Int] = [:]
        for (time, temp) in pointsRaw {
            guard time.wholeMatch(of: timeRegex) != nil else {
                error = "Invalid time format: \(time). Expected HH:mm."
                return nil
            }
            if let t = temp as? Int {
                points[time] = max(55, min(110, t))
            } else if let t = temp as? Double {
                points[time] = max(55, min(110, Int(t)))
            } else {
                error = "Invalid temperature value for \(time)."
                return nil
            }
        }

        guard points.count >= 3 else {
            error = "Need at least 3 set points. Got \(points.count)."
            return nil
        }

        let result = GeneratedCurve(
            bedtime: bedtime,
            wake: wake,
            points: points,
            reasoning: curveJSON["reasoning"] as? String ?? "",
            profileName: curveJSON["name"] as? String ?? "Custom"
        )
        lastResult = result
        return result
    }

    // MARK: - Quick Generate (Local Fallback)

    /// Generate a curve locally from keyword parsing.
    /// No external AI needed -- uses built-in sleep science profiles.
    func generateLocally(prompt: String) -> GeneratedCurve {
        isGenerating = true
        defer { isGenerating = false }

        let lower = prompt.lowercased()

        // Detect preferences from keywords
        let isHot = lower.contains("hot") || lower.contains("warm") || lower.contains("sweat")
        let isCold = lower.contains("cold") || lower.contains("freezing") || lower.contains("chilly")
        let isRecovery = lower.contains("workout") || lower.contains("exercise") || lower.contains("recovery") || lower.contains("run") || lower.contains("gym")

        // Detect times
        let bedtime = extractTime(from: lower, keywords: ["bed", "sleep", "down"]) ?? "22:00"
        let wake = extractTime(from: lower, keywords: ["wake", "alarm", "up", "morning"]) ?? "07:00"

        let profile: SmartProfile
        if isRecovery { profile = .recovery }
        else if isHot { profile = .hotSleeper }
        else if isCold { profile = .coldSleeper }
        else { profile = .balanced }

        // Generate curve from profile
        let calendar = Calendar.current
        let now = Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"

        var bedDate = now
        if let d = fmt.date(from: bedtime) {
            var c = calendar.dateComponents([.year, .month, .day], from: now)
            let tc = calendar.dateComponents([.hour, .minute], from: d)
            c.hour = tc.hour; c.minute = tc.minute
            bedDate = calendar.date(from: c) ?? now
        }

        var wakeDate = now
        if let d = fmt.date(from: wake) {
            var c = calendar.dateComponents([.year, .month, .day], from: now)
            c.day = (c.day ?? 0) + 1
            let tc = calendar.dateComponents([.hour, .minute], from: d)
            c.hour = tc.hour; c.minute = tc.minute
            wakeDate = calendar.date(from: c) ?? now
        }

        let curve = profile.generateCurve(bedtime: bedDate, wakeTime: wakeDate)
        let points = SleepCurve.toScheduleTemperatures(curve)

        var reasoning: String
        if isRecovery {
            reasoning = "Extended deep-cold phase for muscle recovery. Extra cooling in the first half promotes growth hormone release."
        } else if isHot {
            reasoning = "Aggressive cooling with lower minimum to compensate for running warm. Quick ramp down after bedtime."
        } else if isCold {
            reasoning = "Gentle cooling with higher baseline. Warmer pre-wake to avoid waking cold."
        } else {
            reasoning = "Balanced science-backed curve following Heller 2012 and Kr\u{00E4}uchi 2007 research."
        }

        let result = GeneratedCurve(
            bedtime: bedtime,
            wake: wake,
            points: points,
            reasoning: reasoning,
            profileName: profile.name
        )
        lastResult = result
        return result
    }

    private func extractTime(from text: String, keywords: [String]) -> String? {
        // Look for patterns like "11pm", "10:30 pm", "23:00" near keywords
        let timePattern = #"(\d{1,2}):?(\d{2})?\s*(am|pm|AM|PM)?"#
        guard let regex = try? NSRegularExpression(pattern: timePattern) else { return nil }

        for keyword in keywords {
            guard let keyRange = text.range(of: keyword) else { continue }
            let searchStart = max(text.startIndex, text.index(keyRange.lowerBound, offsetBy: -20, limitedBy: text.startIndex) ?? text.startIndex)
            let searchEnd = min(text.endIndex, text.index(keyRange.upperBound, offsetBy: 20, limitedBy: text.endIndex) ?? text.endIndex)
            let searchStr = String(text[searchStart..<searchEnd])

            let nsRange = NSRange(searchStr.startIndex..., in: searchStr)
            if let match = regex.firstMatch(in: searchStr, range: nsRange) {
                var hour = Int((searchStr as NSString).substring(with: match.range(at: 1))) ?? 0
                let minute = match.range(at: 2).location != NSNotFound ?
                    Int((searchStr as NSString).substring(with: match.range(at: 2))) ?? 0 : 0

                if match.range(at: 3).location != NSNotFound {
                    let ampm = (searchStr as NSString).substring(with: match.range(at: 3)).lowercased()
                    if ampm == "pm" && hour < 12 { hour += 12 }
                    if ampm == "am" && hour == 12 { hour = 0 }
                }

                return String(format: "%02d:%02d", hour, minute)
            }
        }
        return nil
    }
}

// MARK: - Curve Template Persistence

struct CurveTemplate: Codable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let points: [String: Int]
    let bedtime: String
    let wake: String
    let reasoning: String

    static let storageKey = "savedCurveTemplates"

    static func loadAll() -> [CurveTemplate] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let templates = try? JSONDecoder().decode([CurveTemplate].self, from: data) else {
            return []
        }
        return templates
    }

    static func save(_ templates: [CurveTemplate]) {
        if let data = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func add(_ template: CurveTemplate) {
        var all = loadAll()
        // Replace if same name exists
        all.removeAll { $0.name == template.name }
        all.insert(template, at: 0)
        save(all)
    }

    static func delete(named name: String) {
        var all = loadAll()
        all.removeAll { $0.name == name }
        save(all)
    }
}
