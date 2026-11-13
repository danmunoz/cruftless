import ServiceManagement

/// The login item registration, as far as Settings needs it.
@MainActor
public protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// Backs the login item with `SMAppService.mainApp`.
public struct SystemLoginItemService: LoginItemService {
    public init() {}

    public var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
