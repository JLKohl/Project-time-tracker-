import Foundation

public enum DurationFormat {
    /// Live clock style, e.g. `1:05:09` or `0:04:30`.
    public static func clock(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    /// Summary style, e.g. `12h 05m`.
    public static func hoursMinutes(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(max(0, interval)) / 60
        return String(format: "%dh %02dm", totalMinutes / 60, totalMinutes % 60)
    }

    /// Totals style: `4m 12s` under an hour, so short sessions visibly count up,
    /// and `12h 05m` from an hour on.
    public static func compact(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        if total < 3600 {
            return String(format: "%dm %02ds", total / 60, total % 60)
        }
        return hoursMinutes(interval)
    }

    /// Reads a target typed by the user: `2`, `1.5`, `1:30`, `2h`, `45m` or `1h 30m`.
    /// Returns `nil` for empty or unreadable text.
    public static func parseHours(_ text: String) -> TimeInterval? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !cleaned.isEmpty else { return nil }

        let colonParts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
        if colonParts.count == 2 {
            guard let hours = Int(colonParts[0]), let minutes = Int(colonParts[1]),
                  hours >= 0, (0..<60).contains(minutes) else { return nil }
            return TimeInterval(hours * 3600 + minutes * 60)
        }

        if let hours = Double(cleaned) {
            return hours.isFinite && hours >= 0 ? hours * 3600 : nil
        }

        // Unit form, e.g. "1h 30m", "2h", "45m", "1.5h".
        var total: TimeInterval = 0
        var number = ""
        var sawUnit = false
        for character in cleaned where character != " " {
            if character.isNumber || character == "." {
                number.append(character)
            } else if character == "h" || character == "m" {
                guard let value = Double(number) else { return nil }
                total += value * (character == "h" ? 3600 : 60)
                number = ""
                sawUnit = true
            } else {
                return nil
            }
        }
        return sawUnit && number.isEmpty ? total : nil
    }

    /// A target written the way a person would type it back in: `2`, `1.5` or `1:20`.
    public static func targetText(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((max(0, interval) / 60).rounded())
        let hours = totalMinutes / 60, minutes = totalMinutes % 60
        switch minutes {
        case 0: return "\(hours)"
        case 30: return "\(hours).5"
        default: return String(format: "%d:%02d", hours, minutes)
        }
    }

    /// Decimal hours, e.g. `12.1` — handy for timesheets and invoices.
    public static func decimalHours(_ interval: TimeInterval) -> String {
        String(format: "%.1f", max(0, interval) / 3600)
    }
}
