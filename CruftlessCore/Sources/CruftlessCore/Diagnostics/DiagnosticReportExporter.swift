import Foundation

public enum DiagnosticReportExportError: Error, Sendable {
    case reportTooLarge
}

public enum DiagnosticReportExporter {
    private static let queue = DispatchQueue(label: "com.danmunoz.cruftless.diagnostic-export", qos: .userInitiated)

    public static func save(_ report: String, to url: URL) async throws {
        guard report.utf8.count <= DiagnosticReportBuilder.maximumBytes + 64 else {
            throw DiagnosticReportExportError.reportTooLarge
        }
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try Data(report.utf8).write(to: url, options: .atomic)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
