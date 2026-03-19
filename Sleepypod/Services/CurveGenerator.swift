import Foundation

/// Generates temperature curves from natural language descriptions.
/// Uses Claude API to interpret sleep preferences and return structured set points.
@MainActor
@Observable
final class CurveGenerator {
    var isGenerating = false
    var error: String?
    var lastResult: GeneratedCurve?

    struct GeneratedCurve: Sendable {
        let bedtime: String      // "HH:mm"
        let wake: String         // "HH:mm"
        let points: [String: Int] // "HH:mm" → tempF
        let reasoning: String
        let profileName: String
    }

    /// Generate a temperature curve from a natural language prompt.
    /// Returns structured set points compatible with the schedule API.
    func generate(prompt: String, currentMinF: Int = 68, currentMaxF: Int = 86) async -> GeneratedCurve? {
        isGenerating = true
        error = nil
        defer { isGenerating = false }

        let systemPrompt = """
        You are a sleep temperature expert for the Sleepypod smart mattress pad. \
        Generate a temperature schedule based on the user's description. \
        The pad controls water temperature from 55°F to 110°F. Typical sleep range is 65-90°F. \
        Science: cooling before sleep promotes deep sleep onset, \
        the body's core temp drops ~2°F by 3am, warming before wake supports cortisol response. \
        Respond ONLY with a JSON object, no other text:
        {"bedtime":"HH:mm","wake":"HH:mm","points":{"HH:mm":tempF,...},"reasoning":"brief explanation","name":"short profile name"}
        Include 8-15 time points spanning bedtime-45min through wake+30min. \
        User's current range: \(currentMinF)°F min, \(currentMaxF)°F max.
        """

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [["role": "user", "content": prompt]]
        ]

        guard let apiKey = UserDefaults.standard.string(forKey: "anthropicAPIKey"), !apiKey.isEmpty else {
            // Fallback: generate locally from keyword parsing
            let result = generateLocally(prompt: prompt, minF: currentMinF, maxF: currentMaxF)
            lastResult = result
            return result
        }

        guard let url = URL(string: "https://api.anthropic.com/v1/messages"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            error = "Invalid request"
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = bodyData
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                error = "API error"
                return generateLocally(prompt: prompt, minF: currentMinF, maxF: currentMaxF)
            }

            // Parse Claude response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = (json["content"] as? [[String: Any]])?.first,
                  let text = content["text"] as? String else {
                error = "Invalid response"
                return generateLocally(prompt: prompt, minF: currentMinF, maxF: currentMaxF)
            }

            // Extract JSON from response (Claude may wrap in markdown)
            let jsonText = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let curveData = jsonText.data(using: .utf8),
                  let curveJSON = try? JSONSerialization.jsonObject(with: curveData) as? [String: Any],
                  let bedtime = curveJSON["bedtime"] as? String,
                  let wake = curveJSON["wake"] as? String,
                  let pointsRaw = curveJSON["points"] as? [String: Any] else {
                error = "Could not parse curve"
                return generateLocally(prompt: prompt, minF: currentMinF, maxF: currentMaxF)
            }

            var points: [String: Int] = [:]
            for (time, temp) in pointsRaw {
                if let t = temp as? Int { points[time] = t }
                else if let t = temp as? Double { points[time] = Int(t) }
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
        } catch {
            self.error = error.localizedDescription
            return generateLocally(prompt: prompt, minF: currentMinF, maxF: currentMaxF)
        }
    }

    // MARK: - Local Fallback (keyword-based)

    private func generateLocally(prompt: String, minF: Int, maxF: Int) -> GeneratedCurve {
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
            reasoning = "Balanced science-backed curve following Heller 2012 and Kräuchi 2007 research."
        }

        return GeneratedCurve(
            bedtime: bedtime,
            wake: wake,
            points: points,
            reasoning: reasoning,
            profileName: profile.name
        )
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
