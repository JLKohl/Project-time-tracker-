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

    /// Decimal hours, e.g. `12.1` — handy for timesheets and invoices.
    public static func decimalHours(_ interval: TimeInterval) -> String {
        String(format: "%.1f", max(0, interval) / 3600)
    }
}
