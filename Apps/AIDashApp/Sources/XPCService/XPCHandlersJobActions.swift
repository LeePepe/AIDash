#if os(macOS)
import Foundation
import AIDashCore

extension XPCHandlers {
    /// Runs before the general store-ready guard so snapshot can report unavailable-store diagnostics.
    /// Throws safe validation/bridge errors; neither route writes an event.
    func handleJobActions(_ request: XPCRequest) throws -> XPCResponse? {
        guard request.command == "job-actions.snapshot" || request.command == "job-actions.present" else { return nil }
        let bridge: JobActionsBridge
        if let existing = jobActionsBridge {
            bridge = existing
        } else {
            bridge = JobActionsBridge.production(container: { [weak self] in self?.container })
            jobActionsBridge = bridge
        }
        let result: Data
        if request.command == "job-actions.snapshot" {
            guard request.params.isEmpty || request.params == Data("{}".utf8) else {
                throw JobActionsBridgeError.make("invalid-request")
            }
            result = try makeXPCEncoder().encode(bridge.snapshot())
        } else {
            let params = try JobActionsValidation.decodePresent(request.params)
            result = try makeXPCEncoder().encode(bridge.present(params))
        }
        return XPCResponse(
            requestId: request.requestId, appVersion: Self.appVersion, ok: true, data: result, error: nil
        )
    }
}
#endif
