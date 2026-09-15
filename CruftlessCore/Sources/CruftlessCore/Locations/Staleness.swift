import Foundation

public enum StalenessSource: Sendable, Hashable, Codable, CaseIterable {
    case topLevelMtime
    case newestChildMtime
    case archiveCreationDate
    case simulatorPlist
}

public enum Staleness: Sendable {
    public static func resolve(
        source: StalenessSource,
        archiveCreationDate: @autoclosure () -> Date?,
        simulatorLastUsedAt: @autoclosure () -> Date?,
        newestChildMtime: @autoclosure () -> Date?,
        topLevelMtime: @autoclosure () -> Date?
    ) -> StalenessInfo {
        switch source {
        case .archiveCreationDate:
            StalenessInfo(lastUsedDate: archiveCreationDate())
        case .simulatorPlist:
            StalenessInfo(lastUsedDate: simulatorLastUsedAt())
        case .newestChildMtime:
            StalenessInfo(lastUsedDate: newestChildMtime())
        case .topLevelMtime:
            StalenessInfo(lastUsedDate: topLevelMtime())
        }
    }
}

public struct StalenessInfo: Sendable, Hashable, Codable {
    public let lastUsedDate: Date?

    public init(lastUsedDate: Date?) {
        self.lastUsedDate = lastUsedDate
    }

    public func isStale(now: Date = Date(), thresholdDays: Int = 30) -> Bool {
        guard let lastUsedDate else { return false }
        let days = Calendar.current.dateComponents([.day], from: lastUsedDate, to: now).day ?? 0
        return days >= thresholdDays
    }

    /// A label for a stale entry, for example, `"Unused for 6 weeks"`.
    public func stalenessLabel(now: Date = .now, thresholdDays: Int = 30) -> String? {
        guard let lastUsedDate, isStale(now: now, thresholdDays: thresholdDays) else {
            return nil
        }

        let days = max(0, Calendar.current.dateComponents([.day], from: lastUsedDate, to: now).day ?? 0)

        if days < 14 {
            return "Unused for \(Self.pluralized(days, "day"))"
        } else if days < 56 {
            return "Unused for \(Self.pluralized(days / 7, "week"))"
        } else if days < 360 {
            return "Unused for \(Self.pluralized(days / 30, "month"))"
        } else {
            return "Unused for \(Self.pluralized(days / 365, "year"))"
        }
    }

    private static func pluralized(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s")"
    }
}
