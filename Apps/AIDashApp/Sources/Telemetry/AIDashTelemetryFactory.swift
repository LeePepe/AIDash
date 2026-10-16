import Foundation
import LokiKit

struct AIDashTelemetryHostConfiguration: Equatable {
    let endpoint: String?
    let sas: String?
    let app: String
    let build: String
    let storeDirectory: URL

    init(
        endpoint: String?,
        sas: String?,
        app: String,
        build: String,
        storeDirectory: URL = (FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser)
            .appendingPathComponent("AIDash/Telemetry", isDirectory: true)
    ) {
        self.endpoint = endpoint
        self.sas = sas
        self.app = app
        self.build = build
        self.storeDirectory = storeDirectory
    }

    static func production(bundle: Bundle = .main) -> AIDashTelemetryHostConfiguration {
        AIDashTelemetryHostConfiguration(
            endpoint: bundle.object(forInfoDictionaryKey: "LokiKitBlobEndpoint") as? String,
            sas: bundle.object(forInfoDictionaryKey: "LokiKitBlobSAS") as? String,
            app: "aidash",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        )
    }
}

struct AIDashTelemetryValidatedConfiguration: Equatable {
    let endpoint: URL
    let sas: String
    let app: String
    let build: String
    let storeDirectory: URL
    let installID: UUID
}

@MainActor
protocol AIDashTelemetryServicing: AnyObject {
    var isEnabled: Bool { get set }
    func track(_ event: AIDashTelemetryEvent)
    func flush() async
}

@MainActor
struct AIDashTelemetryFactory {
    typealias Builder = (AIDashTelemetryValidatedConfiguration) -> AIDashTelemetryServicing?

    private let builder: Builder

    init(builder: @escaping Builder) {
        self.builder = builder
    }

    func make(
        configuration: AIDashTelemetryHostConfiguration,
        installID: UUID
    ) -> AIDashTelemetryServicing? {
        guard let validated = Self.validate(configuration, installID: installID) else {
            return nil
        }
        return builder(validated)
    }

    private static func validate(
        _ configuration: AIDashTelemetryHostConfiguration,
        installID: UUID
    ) -> AIDashTelemetryValidatedConfiguration? {
        guard let endpointString = configuration.endpoint?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let sas = configuration.sas?.trimmingCharacters(in: .whitespacesAndNewlines),
            !endpointString.isEmpty,
            !sas.isEmpty,
            !endpointString.contains("$("),
            !sas.contains("$("),
            let endpoint = URL(string: endpointString),
            let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
            components.scheme == "https",
            components.host != nil,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil,
            components.percentEncodedPath.range(
                of: "^/[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$",
                options: .regularExpression
            ) != nil,
            !components.path.contains("--"),
            validSegment(configuration.app),
            validSegment(configuration.build),
            validSAS(sas) else {
            return nil
        }
        return AIDashTelemetryValidatedConfiguration(
            endpoint: endpoint,
            sas: sas,
            app: configuration.app,
            build: configuration.build,
            storeDirectory: configuration.storeDirectory,
            installID: installID
        )
    }

    private static func validSAS(_ value: String) -> Bool {
        let query = value.hasPrefix("?") ? String(value.dropFirst()) : value
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/?%"
        )
        guard !query.isEmpty,
              query.removingPercentEncoding != nil,
              query.rangeOfCharacter(from: allowed.inverted) == nil else {
            return false
        }
        var components = URLComponents()
        components.percentEncodedQuery = query
        guard let items = components.queryItems else { return false }
        let names = Set(items.map(\.name))
        let supported = Set(["sv", "sr", "si", "sp", "st", "se", "spr", "sip", "sig"])
        return names.count == items.count
            && names.isSubset(of: supported)
            && items.contains { $0.name == "sig" && !($0.value ?? "").isEmpty }
            && items.contains { $0.name == "sr" && $0.value == "c" }
            && !items.contains { $0.name == "sp" && $0.value != "c" }
            && !items.contains { $0.name == "spr" && $0.value != "https" }
    }

    private static func validSegment(_ value: String) -> Bool {
        !value.isEmpty
            && !value.hasSuffix(".")
            && !value.contains("/")
            && !value.contains("\\")
            && value.rangeOfCharacter(from: .controlCharacters) == nil
    }

    static let live = AIDashTelemetryFactory { configuration in
        let privacy = AzureBlobPrivacyPolicy(
            events: [
                "aidash.action": [
                    "action_name": .label(["briefing_viewed"]),
                ],
                "aidash.performance.ready_scene": [
                    "duration_ms": .finiteNumber,
                ],
            ],
            apps: [configuration.app],
            builds: [configuration.build]
        )
        do {
            let service = try AzureBlobTelemetryService(
                containerURL: configuration.endpoint,
                sasQuery: configuration.sas,
                app: configuration.app,
                build: configuration.build,
                privacy: privacy,
                storeDirectory: configuration.storeDirectory,
                isEnabled: true,
                identityProvider: { configuration.installID },
                heartbeatVersion: nil
            )
            return AIDashLokiTelemetryService(service: service)
        } catch {
            return nil
        }
    }
}

@MainActor
private final class AIDashLokiTelemetryService: AIDashTelemetryServicing {
    private let service: AzureBlobTelemetryService

    init(service: AzureBlobTelemetryService) {
        self.service = service
    }

    var isEnabled: Bool {
        get { service.isEnabled }
        set { service.isEnabled = newValue }
    }

    func track(_ event: AIDashTelemetryEvent) {
        service.track(TelemetryEvent(
            name: event.name,
            properties: event.properties,
            timestamp: event.timestamp
        ))
    }

    func flush() async {
        await service.flush()
    }
}
