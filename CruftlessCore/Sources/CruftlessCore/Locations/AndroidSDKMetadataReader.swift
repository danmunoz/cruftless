import Darwin
import Foundation

struct AndroidSDKMetadataResult {
    let package: AndroidSDKPackage?
    let diagnostic: AndroidSDKDiagnostic?
}

enum AndroidSDKMetadataReader {
    static let maximumBytes = 64 * 1024

    static func read(directory: URL, root: URL) -> AndroidSDKMetadataResult {
        guard let expected = RootResolver.sdkPackagePath(for: directory, sdkRoot: root) else {
            return AndroidSDKMetadataResult(package: nil, diagnostic: nil)
        }
        var source = readFile(directory.appendingPathComponent("source.properties"))
        var xml = readFile(directory.appendingPathComponent("package.xml"))
        let values = source.data.flatMap { SDKProperties.parse($0) }
        if source.status == .valid, values == nil { source.status = .malformed }
        let record = xml.data.flatMap { SDKPackageXML.read($0) }
        if xml.status == .valid, record == nil { xml.status = .malformed }

        let sourcePath = values?["Pkg.Path"]
        let revision = record?.revision ?? values?["Pkg.Revision"]
        let xmlMatches = record.map { matches($0.path, expected: expected, revision: revision) } ?? true
        let sourceMatches = sourcePath.map { matches($0, expected: expected, revision: revision) } ?? true
        let aliasRevisionMatches = expected == "cmdline-tools;latest"
            ? revisionsAgree(record?.revision, values?["Pkg.Revision"])
            : true
        let conflict = !xmlMatches || !sourceMatches || !aliasRevisionMatches
        if !xmlMatches || !aliasRevisionMatches { xml.status = .conflicting }
        if !sourceMatches || !aliasRevisionMatches { source.status = .conflicting }
        let identityMatches = !conflict && (record != nil || sourcePath != nil)
        let hasPropertiesIdentity = values.map {
            $0["Pkg.Path"] != nil || $0["Pkg.Desc"]?.isEmpty == false || $0["Pkg.Revision"]?.isEmpty == false
        } ?? false
        let package: AndroidSDKPackage? = if !conflict, record != nil || hasPropertiesIdentity {
            AndroidSDKPackage(
                displayName: record?.name ?? values?["Pkg.Desc"] ?? expected,
                packagePath: expected,
                revision: revision
            )
        } else { nil }
        let reason = reason(for: source.status, xml.status, conflict: conflict, recognized: package != nil)
        let diagnostic = reason.map {
            AndroidSDKDiagnostic(
                relativePath: expected.replacingOccurrences(of: ";", with: "/"),
                category: category(for: expected),
                packageIdentity: expected,
                reason: $0,
                sourcePropertiesStatus: source.status,
                packageXMLStatus: xml.status,
                identityMatchesLayout: identityMatches,
                sourcePropertiesBytes: source.bytes,
                packageXMLBytes: xml.bytes
            )
        }
        return AndroidSDKMetadataResult(package: package, diagnostic: diagnostic)
    }

    private struct MetadataFile {
        var status: DiagnosticMetadataStatus
        let data: Data?
        let bytes: Int?
    }

    private static func readFile(_ url: URL) -> MetadataFile {
        let path = url.path(percentEncoded: false)
        var metadata = stat()
        guard lstat(path, &metadata) == 0 else {
            return MetadataFile(status: errno == ENOENT ? .missing : .unreadable, data: nil, bytes: nil)
        }
        guard (metadata.st_mode & S_IFMT) != S_IFLNK else {
            return MetadataFile(status: .symlink, data: nil, bytes: nil)
        }
        let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return MetadataFile(status: .unreadable, data: nil, bytes: nil) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            return MetadataFile(status: .unreadable, data: nil, bytes: nil)
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            return MetadataFile(status: .unsupported, data: nil, bytes: nil)
        }
        guard metadata.st_size >= 0, metadata.st_size <= maximumBytes else {
            return MetadataFile(status: .tooLarge, data: nil, bytes: nil)
        }
        return readDescriptor(descriptor)
    }

    private static func readDescriptor(_ descriptor: Int32) -> MetadataFile {
        var data = Data()
        while data.count <= maximumBytes {
            var buffer = [UInt8](repeating: 0, count: min(8192, maximumBytes + 1 - data.count))
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                return MetadataFile(status: .unreadable, data: nil, bytes: nil)
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count <= maximumBytes else {
            return MetadataFile(status: .tooLarge, data: nil, bytes: nil)
        }
        guard String(data: data, encoding: .utf8) != nil else {
            return MetadataFile(status: .invalidEncoding, data: nil, bytes: data.count)
        }
        return MetadataFile(status: .valid, data: data, bytes: data.count)
    }

    private static func matches(_ claimed: String, expected: String, revision: String?) -> Bool {
        if claimed == expected { return true }
        guard expected == "cmdline-tools;latest", claimed.hasPrefix("cmdline-tools;"), let revision else { return false }
        let version = String(claimed.dropFirst("cmdline-tools;".count))
        guard numericVersion(version), numericVersion(revision) else { return false }
        return canonicalVersion(version) == canonicalVersion(revision)
    }

    private static func revisionsAgree(_ first: String?, _ second: String?) -> Bool {
        guard let first, let second else { return true }
        return numericVersion(first) && numericVersion(second) && canonicalVersion(first) == canonicalVersion(second)
    }

    private static func numericVersion(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48 ... 57).contains($0) || $0 == 46 }
            && value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty }
    }

    private static func canonicalVersion(_ value: String) -> [Substring] {
        var components = value.split(separator: ".")
        while components.count > 1, components.last == "0" {
            components.removeLast()
        }
        return components
    }

    private static func reason(
        for source: DiagnosticMetadataStatus,
        _ xml: DiagnosticMetadataStatus,
        conflict: Bool,
        recognized: Bool
    ) -> AndroidSDKDiagnosticReason? {
        if conflict { return .conflictingIdentity }
        let statuses = [source, xml]
        if statuses.contains(.symlink) { return .symlinkMetadata }
        if statuses.contains(.tooLarge) { return .oversizedMetadata }
        if statuses.contains(.unreadable) { return .unreadableMetadata }
        if statuses.contains(.unsupported) { return .nonRegularMetadata }
        if statuses.contains(.invalidEncoding) { return .invalidEncoding }
        if xml == .malformed { return .malformedXML }
        if source == .malformed { return .malformedProperties }
        return recognized ? nil : .missingMetadata
    }

    private static func category(for identity: String) -> DiagnosticSDKCategory {
        let categories: [String: DiagnosticSDKCategory] = [
            "platforms": .platform, "build-tools": .buildTools, "system-images": .systemImage,
            "ndk": .ndk, "cmake": .cmake, "cmdline-tools": .commandLineTools,
            "emulator": .emulator, "platform-tools": .platformTools, "sources": .sources, "extras": .extras
        ]
        return identity.split(separator: ";").first.flatMap { categories[String($0)] } ?? .unknown
    }
}

private final class SDKPackageXML: NSObject, XMLParserDelegate {
    private(set) var path = ""
    private(set) var name: String?
    private(set) var revision: String?
    private var elements: [String] = []
    private var text = ""
    private var parts: [String: String] = [:]
    private var packageCount = 0

    static func read(_ data: Data) -> SDKPackageXML? {
        guard let text = String(data: data, encoding: .utf8),
              !text.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !text.localizedCaseInsensitiveContains("<!ENTITY") else { return nil }
        let result = SDKPackageXML()
        let parser = XMLParser(data: data)
        parser.delegate = result
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), result.packageCount == 1, !result.path.isEmpty else { return nil }
        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI _: String?,
                qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
        let element = elementName.split(separator: ":").last.map(String.init) ?? elementName
        elements.append(element)
        text = ""
        if element == "localPackage" {
            packageCount += 1
            guard packageCount == 1, elements.count == 2, elements.first == "repository" else {
                parser.abortParsing()
                return
            }
            path = attributeDict["path"] ?? ""
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement _: String, namespaceURI _: String?, qualifiedName _: String?) {
        guard let element = elements.last else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if elements == ["repository", "localPackage", "display-name"], !value.isEmpty { name = value }
        if elements.count == 4, elements[1] == "localPackage", elements[2] == "revision",
           ["major", "minor", "micro"].contains(element) {
            guard parts[element] == nil, !value.isEmpty, value.utf8.allSatisfy({ (48 ... 57).contains($0) }) else {
                parser.abortParsing()
                return
            }
            parts[element] = value
        }
        if elements == ["repository", "localPackage", "revision"], parts["major"] != nil {
            revision = ["major", "minor", "micro"].compactMap { parts[$0] }.joined(separator: ".")
        }
        elements.removeLast()
        text = ""
    }
}
