import Foundation
import Testing
#if AIDASHAPP_LOGIC_TESTS
@testable import AIDashAppLogic
#else
@testable import AIDashApp
#endif

@Suite("AIDash telemetry factory")
@MainActor
struct AIDashTelemetryFactoryTests {
    @Test("invalid host configuration constructs nothing")
    func invalidConfiguration() {
        var constructions = 0
        let factory = AIDashTelemetryFactory { _ in
            constructions += 1
            return TelemetryServiceSpy()
        }
        let invalid = [
            AIDashTelemetryHostConfiguration(endpoint: nil, sas: nil, app: "aidash", build: "1"),
            AIDashTelemetryHostConfiguration(endpoint: "", sas: "sig=x", app: "aidash", build: "1"),
            AIDashTelemetryHostConfiguration(
                endpoint: "$(TELEMETRY_BLOB_ENDPOINT)",
                sas: "sig=x",
                app: "aidash",
                build: "1"
            ),
            AIDashTelemetryHostConfiguration(
                endpoint: "http://example.invalid/container",
                sas: "sig=x",
                app: "aidash",
                build: "1"
            ),
            AIDashTelemetryHostConfiguration(
                endpoint: "https://example.invalid/not--a-container",
                sas: "sv=neutral&sr=c&sp=c&sig=value",
                app: "aidash",
                build: "1"
            ),
            AIDashTelemetryHostConfiguration(
                endpoint: "https://example.invalid/container",
                sas: "sv=neutral&sr=c&sp=c&sig=bad%ZZ",
                app: "aidash",
                build: "1"
            ),
        ]

        for configuration in invalid {
            #expect(factory.make(configuration: configuration, installID: UUID()) == nil)
        }
        #expect(constructions == 0)
    }

    @Test("SAS accepts only reviewed create-only service and stored-policy forms")
    func sasCapabilityBoundary() {
        var constructions = 0
        let factory = AIDashTelemetryFactory { _ in
            constructions += 1
            return TelemetryServiceSpy()
        }
        let invalidSASValues = [
            "sv=neutral&sr=c&sig=value",
            "sv=neutral&sr=c&si=&sig=value",
            "sv=neutral&sr=c&sp=&sig=value",
            "sv=neutral&sr=c&sp=r&sig=value",
            "sv=neutral&sr=c&sp=a&sig=value",
            "sv=neutral&sr=c&sp=w&sig=value",
            "sv=neutral&sr=c&sp=d&sig=value",
            "sv=neutral&sr=c&sp=l&sig=value",
            "sv=neutral&sr=c&sp=t&sig=value",
            "sv=neutral&sr=c&sp=m&sig=value",
            "sv=neutral&sr=c&sp=e&sig=value",
            "sv=neutral&sr=c&sp=o&sig=value",
            "sv=neutral&sr=c&sp=p&sig=value",
            "sv=neutral&sr=c&sp=i&sig=value",
            "sv=neutral&sr=c&sp=cc&sig=value",
            "sv=neutral&sr=c&sp=cr&sig=value",
            "sv=neutral&sr=c&sp=C&sig=value",
            "sv=neutral&sr=c&si=policy&si=other&sig=value",
            "sv=neutral&sr=c&sr=c&sp=c&sig=value",
            "sv=neutral&sr=c&sp=c&sp=c&sig=value",
            "sv=neutral&sr=c&si=policy&sig=&spr=https",
            "sv=neutral&sr=c&si=policy&sig=value&sig=other",
            "sv=neutral&sp=c&sig=value",
            "sv=neutral&sr=b&sp=c&sig=value",
            "sv=neutral&sr=c&si=policy&spr=http&sig=value",
            "sv=neutral&sr=c&si=policy&skoid=value&sig=value",
            "sv=neutral&sr=c&si=policy&sktid=value&sig=value",
            "sv=neutral&sr=c&si=policy&skt=value&sig=value",
            "sv=neutral&sr=c&si=policy&ske=value&sig=value",
            "sv=neutral&sr=c&si=policy&sks=value&sig=value",
            "sv=neutral&sr=c&si=policy&skv=value&sig=value",
            "sv=neutral&sr=c&si=policy&saoid=value&sig=value",
            "sv=neutral&sr=c&si=policy&suoid=value&sig=value",
            "sv=neutral&sr=c&si=policy&scid=value&sig=value",
            "sv=neutral&sr=c&sp=c&unsupported=value&sig=value",
        ]

        for sas in invalidSASValues {
            let configuration = AIDashTelemetryHostConfiguration(
                endpoint: "https://example.invalid/container",
                sas: sas,
                app: "aidash",
                build: "1"
            )
            #expect(factory.make(configuration: configuration, installID: UUID()) == nil)
        }
        #expect(constructions == 0)

        for sas in [
            "sv=neutral&sr=c&sp=c&sig=value",
            "sv=neutral&sr=c&si=policy&sig=value",
            "sv=neutral&sr=c&si=policy&spr=https&sig=value",
            "sv=neutral&sr=c&sp=c&si=policy&sig=value",
        ] {
            let configuration = AIDashTelemetryHostConfiguration(
                endpoint: "https://example.invalid/container",
                sas: sas,
                app: "aidash",
                build: "1"
            )
            #expect(factory.make(configuration: configuration, installID: UUID()) != nil)
        }
        #expect(constructions == 4)
    }

    @Test("valid configuration reaches the direct builder once")
    func validConfiguration() {
        var received: AIDashTelemetryValidatedConfiguration?
        let service = TelemetryServiceSpy()
        let factory = AIDashTelemetryFactory {
            received = $0
            return service
        }
        let identifier = UUID()
        let configuration = AIDashTelemetryHostConfiguration(
            endpoint: "https://example.invalid/container",
            sas: "sv=neutral&sr=c&sp=c&sig=value",
            app: "aidash",
            build: "42"
        )

        #expect(factory.make(configuration: configuration, installID: identifier) === service)
        #expect(received?.installID == identifier)
        #expect(received?.endpoint.absoluteString == "https://example.invalid/container")
        #expect(received?.storeDirectory.lastPathComponent == "Telemetry")
        #expect(received?.storeDirectory.deletingLastPathComponent().lastPathComponent == "AIDash")
    }

    @Test("accepted stored-policy SAS bytes reach the builder unchanged")
    func storedPolicySASBytePreservation() {
        var received: AIDashTelemetryValidatedConfiguration?
        let factory = AIDashTelemetryFactory {
            received = $0
            return TelemetryServiceSpy()
        }
        let sas = "?sig=a%2Bb%2Fc%3D&spr=https&si=policy%2Dname&sr=c&sv=neutral"
        let configuration = AIDashTelemetryHostConfiguration(
            endpoint: "https://example.invalid/container",
            sas: sas,
            app: "aidash",
            build: "1"
        )

        #expect(factory.make(configuration: configuration, installID: UUID()) != nil)
        #expect(received?.sas == sas)
    }
}

@MainActor
final class TelemetryServiceSpy: AIDashTelemetryServicing {
    var isEnabled = true
    var events: [AIDashTelemetryEvent] = []
    var flushCount = 0
    var flushHandler: (() async -> Void)?

    func track(_ event: AIDashTelemetryEvent) {
        events.append(event)
    }

    func flush() async {
        flushCount += 1
        await flushHandler?()
    }
}
