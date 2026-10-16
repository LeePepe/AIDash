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
    }
}

@MainActor
final class TelemetryServiceSpy: AIDashTelemetryServicing {
    var isEnabled = true
    var events: [AIDashTelemetryEvent] = []
    var flushCount = 0

    func track(_ event: AIDashTelemetryEvent) {
        events.append(event)
    }

    func flush() async {
        flushCount += 1
    }
}
