import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(IOKit)
import IOKit
#endif

/// Produces a stable, human-readable device identifier string.
///
/// Format: `"<deviceName> [<UUID8>]"`, e.g. `"Tianpli's iPhone [3F2A4B1C]"`.
/// The name portion changes when the user renames the device; the 8-char
/// hex suffix stays the same across renames.
public enum DeviceIdentifier {

    /// Returns a non-empty device identifier in the format `"<name> [<UUID8>]"`.
    /// Cheap to call — no async, no throws. The stable UUID is computed once
    /// and cached for the process lifetime.
    public static func current() -> String {
        let name = readableName()
        let suffix = String(cachedStableUUID.prefix(8)).uppercased()
        return "\(name) [\(suffix)]"
    }

    // MARK: - Cached UUID (computed once per process)

    /// Lazily computed, thread-safe (`static let` is `dispatch_once` under
    /// the hood). Avoids repeated IOKit lookups on macOS and guarantees
    /// the suffix is identical across calls even when the underlying
    /// source is per-call (e.g. `globallyUniqueString`).
    private static let cachedStableUUID: String = {
        #if os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
        // Use a persisted UUID to avoid MainActor-isolated UIDevice access
        // in a nonisolated context (Swift 6 strict concurrency).
        let key = "com.aidash.DeviceIdentifier.fallbackUUID"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
        #elseif os(macOS)
        if let hwUUID = macOSHardwareUUID() { return hwUUID }
        return ProcessInfo.processInfo.globallyUniqueString
        #else
        return ProcessInfo.processInfo.globallyUniqueString
        #endif
    }()

    // MARK: - Private

    private static func readableName() -> String {
        #if os(iOS) || os(visionOS) || os(tvOS) || os(watchOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }

    #if os(macOS)
    private static func macOSHardwareUUID() -> String? {
        let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict)
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        guard let uuidRef = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }

        return uuidRef.takeRetainedValue() as? String
    }
    #endif
}
