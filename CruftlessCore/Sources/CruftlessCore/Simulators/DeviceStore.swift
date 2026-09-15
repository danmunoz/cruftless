import Darwin
import Foundation

public enum DeviceStore: Sendable {
    /// The default argument for `loadDevices(from:)`.
    public static var defaultDevicesDirectory: URL {
        if let resolved = RootResolver.simulatorDevicesRoot().first {
            return resolved
        }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return home.appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)
    }

    public static func loadDevices(
        from devicesDirectory: URL = DeviceStore.defaultDevicesDirectory
    ) -> [SimDevice] {
        let path = devicesDirectory.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        guard let dir = opendir(path) else { return [] }
        defer { closedir(dir) }

        var devices: [SimDevice] = []

        while let entry = readdir(dir) {
            guard let name = Dirent.name(of: entry) else { continue }

            if name == "." || name == ".." || name.hasPrefix(".") {
                continue
            }

            let deviceDir = devicesDirectory.appendingPathComponent(name, isDirectory: true)
            let plistURL = deviceDir.appendingPathComponent("device.plist")

            if let device = parseDevicePlist(at: plistURL, deviceDirectory: deviceDir) {
                devices.append(device)
            }
        }

        return devices
    }

    public static func parseDevicePlist(at plistURL: URL, deviceDirectory: URL) -> SimDevice? {
        guard let data = try? Data(contentsOf: plistURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }

        // Ignore deleted or ephemeral simulators.
        if let isDeleted = dict["isDeleted"] as? Bool, isDeleted {
            return nil
        }

        // A UDID that is not a UUID never reaches `simctl`: `all` or `booted` in that slot would widen an erase to every device.
        guard let rawUDID = dict["UDID"] as? String ?? dict["udid"] as? String,
              let udid = try? SimctlIdentifier.validatedUDID(rawUDID),
              let name = dict["name"] as? String
        else {
            return nil
        }

        let runtime = dict["runtime"] as? String ?? ""

        let stateRaw = dict["state"] as? Int ?? 0
        let state = SimDeviceState(rawValue: stateRaw) ?? .other

        let lastUsedAt = dict["lastUsedAt"] as? Date

        return SimDevice(
            udid: udid,
            name: name,
            runtime: runtime,
            state: state,
            lastUsedAt: lastUsedAt,
            deviceDirectory: deviceDirectory
        )
    }
}
