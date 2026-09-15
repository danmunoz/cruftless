import Foundation

public enum ByteFormatter: Sendable {
    public static func format(_ bytes: Int64, locale: Locale = .autoupdatingCurrent) -> String {
        if bytes <= 0 {
            return "0 B"
        }

        let doubleBytes = Double(bytes)
        let kilobyte: Double = 1000
        let megabyte: Double = 1000 * kilobyte
        let gigabyte: Double = 1000 * megabyte
        let terabyte: Double = 1000 * gigabyte

        if doubleBytes < kilobyte {
            return "\(bytes) B"
        } else if doubleBytes < megabyte {
            let val = doubleBytes / kilobyte
            return formatNumber(val, unit: "KB", locale: locale)
        } else if doubleBytes < gigabyte {
            let val = doubleBytes / megabyte
            return formatNumber(val, unit: "MB", locale: locale)
        } else if doubleBytes < terabyte {
            let val = doubleBytes / gigabyte
            return formatNumber(val, unit: "GB", locale: locale)
        } else {
            let val = doubleBytes / terabyte
            return formatNumber(val, unit: "TB", locale: locale)
        }
    }

    private static func formatNumber(_ value: Double, unit: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = unit == "GB" || unit == "TB" ? 1 : 0
        let formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        return "\(formatted) \(unit)"
    }
}
