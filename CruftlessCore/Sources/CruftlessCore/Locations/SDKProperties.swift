import Foundation

enum SDKProperties {
    static func parse(_ data: Data) -> [String: String]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        var pending = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = pending.isEmpty ? raw : raw.trimmingCharacters(in: .whitespaces)
            pending += line
            let backslashes = pending.reversed().prefix(while: { $0 == "\\" }).count
            if backslashes % 2 == 1 {
                pending.removeLast()
                continue
            }
            let logicalLine = pending
            pending = ""
            let trimmed = logicalLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("!") { continue }
            guard let property = RootResolver.parseProperty(trimmed),
                  let key = decode(property.key), let value = decode(property.value) else { return nil }
            if let previous = values[key], previous != value { return nil }
            values[key] = value
        }
        guard pending.isEmpty else { return nil }
        return values.isEmpty ? nil : values
    }

    private static func decode(_ value: String) -> String? {
        var result: [UInt16] = []
        let units = Array(value.utf16)
        var index = 0
        while index < units.count {
            let unit = units[index]
            index += 1
            guard unit == 92 else { result.append(unit)
                continue
            }
            guard index < units.count else { return nil }
            let escaped = units[index]
            index += 1
            if escaped == 117 {
                guard index + 4 <= units.count else { return nil }
                let hex = String(decoding: units[index ..< (index + 4)], as: UTF16.self)
                guard let scalar = UInt16(hex, radix: 16) else { return nil }
                result.append(scalar)
                index += 4
            } else {
                let escapes: [UInt16: UInt16] = [116: 9, 114: 13, 110: 10, 102: 12]
                result.append(escapes[escaped] ?? escaped)
            }
        }
        return String(decoding: result, as: UTF16.self)
    }
}
