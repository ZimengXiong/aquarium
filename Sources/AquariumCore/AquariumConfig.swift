import Foundation

public struct AquariumConfig: Codable, Equatable {
    public var enabled: Bool
    public var preventLidSleep: Bool
    public var appFilterEnabled: Bool
    public var allowedApps: [AllowedApp]
    public var allowedCLIProcesses: [AllowedCLIProcess]
    public var turnOffBrightnessWhenLidClosed: Bool
    public var batteryGateEnabled: Bool
    public var minimumBatteryPercent: Int
    public var autoDisableBatteryEnabled: Bool
    public var autoDisableBatteryPercent: Int
    public var launchAtLogin: Bool

    public init(
        enabled: Bool = false,
        preventLidSleep: Bool = true,
        appFilterEnabled: Bool = false,
        allowedApps: [AllowedApp] = [],
        allowedCLIProcesses: [AllowedCLIProcess] = [],
        turnOffBrightnessWhenLidClosed: Bool = true,
        batteryGateEnabled: Bool = true,
        minimumBatteryPercent: Int = 20,
        autoDisableBatteryEnabled: Bool = true,
        autoDisableBatteryPercent: Int = 10,
        launchAtLogin: Bool = false
    ) {
        self.enabled = enabled
        self.preventLidSleep = preventLidSleep
        self.appFilterEnabled = appFilterEnabled
        self.allowedApps = allowedApps
        self.allowedCLIProcesses = allowedCLIProcesses
        self.turnOffBrightnessWhenLidClosed = turnOffBrightnessWhenLidClosed
        self.batteryGateEnabled = batteryGateEnabled
        self.minimumBatteryPercent = minimumBatteryPercent
        self.autoDisableBatteryEnabled = autoDisableBatteryEnabled
        self.autoDisableBatteryPercent = autoDisableBatteryPercent
        self.launchAtLogin = launchAtLogin
    }

    public mutating func normalizeForSave(previous: AquariumConfig?) {
        allowedApps = Array(Dictionary(grouping: allowedApps, by: \.executableName).compactMap { $0.value.first })
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        allowedCLIProcesses = Array(Dictionary(grouping: allowedCLIProcesses, by: \.name).compactMap { $0.value.first })
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        minimumBatteryPercent = min(100, max(1, minimumBatteryPercent))
        autoDisableBatteryPercent = min(100, max(1, autoDisableBatteryPercent))
    }

    public static let defaultPath = "/Library/Application Support/Aquarium/config.json"

    private enum CodingKeys: String, CodingKey {
        case enabled
        case preventLidSleep
        case appFilterEnabled
        case allowedApps
        case allowedCLIProcesses
        case turnOffBrightnessWhenLidClosed
        case batteryGateEnabled
        case minimumBatteryPercent
        case autoDisableBatteryEnabled
        case autoDisableBatteryPercent
        case launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        preventLidSleep = try container.decodeIfPresent(Bool.self, forKey: .preventLidSleep) ?? true
        appFilterEnabled = try container.decodeIfPresent(Bool.self, forKey: .appFilterEnabled) ?? false
        allowedApps = try container.decodeIfPresent([AllowedApp].self, forKey: .allowedApps) ?? []
        allowedCLIProcesses = try container.decodeIfPresent([AllowedCLIProcess].self, forKey: .allowedCLIProcesses) ?? []
        turnOffBrightnessWhenLidClosed = try container.decodeIfPresent(Bool.self, forKey: .turnOffBrightnessWhenLidClosed) ?? true
        batteryGateEnabled = try container.decodeIfPresent(Bool.self, forKey: .batteryGateEnabled) ?? true
        minimumBatteryPercent = try container.decodeIfPresent(Int.self, forKey: .minimumBatteryPercent) ?? 20
        autoDisableBatteryEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoDisableBatteryEnabled) ?? true
        autoDisableBatteryPercent = try container.decodeIfPresent(Int.self, forKey: .autoDisableBatteryPercent) ?? 10
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        normalizeForSave(previous: nil)
    }
}

public struct AllowedApp: Codable, Equatable, Identifiable {
    public var id: String { executableName }
    public var name: String
    public var bundleIdentifier: String?
    public var executableName: String
    public var path: String
    public var enabled: Bool

    public init(name: String, bundleIdentifier: String?, executableName: String, path: String, enabled: Bool = true) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
        self.path = path
        self.enabled = enabled
    }
}

public struct AllowedCLIProcess: Codable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var enabled: Bool

    public init(name: String, enabled: Bool = true) {
        self.name = name
        self.enabled = enabled
    }
}

public enum AquariumConfigStore {
    public static func load(path: String = AquariumConfig.defaultPath) throws -> AquariumConfig {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AquariumConfig.self, from: data)
    }

    public static func save(_ config: AquariumConfig, path: String = AquariumConfig.defaultPath) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        do {
            // Prefer an atomic write: it is crash-safe. But an atomic write stages a
            // temporary file in the parent directory and renames it into place, so it
            // needs write access to the directory, not just the target file. config.json
            // is installed group-writable (664 root:staff) inside a root-owned directory
            // so the unprivileged menu bar app can update it; if that directory is created
            // root:wheel instead, the app user cannot stage the temp file and every
            // settings change (e.g. the enable toggle) is silently dropped.
            try data.write(to: url, options: [.atomic])
        } catch {
            // Only fall back for a permission failure we can actually repair: the file
            // itself is writable even though its directory is not. Rethrow anything else
            // (out of space, I/O) so a doomed write never truncates a valid config.
            guard isPermissionDenied(error), FileManager.default.isWritableFile(atPath: path) else {
                throw error
            }
            // In-place write: needs write access to the existing file only, not to the
            // directory. Not atomic, but strictly better than dropping the change.
            try data.write(to: url, options: [])
        }
    }

    private static func isPermissionDenied(_ error: Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .fileWriteNoPermission {
            return true
        }
        let nsError = error as NSError
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == Int(EACCES) || underlying.code == Int(EPERM) {
            return true
        }
        return false
    }
}
