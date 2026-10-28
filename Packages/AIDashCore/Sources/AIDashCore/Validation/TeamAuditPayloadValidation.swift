import Foundation

extension TeamAuditPayload {
    public func validateInvariants() throws {
        try validateStructuralInvariants()
        try TeamAuditPayloadURLValidator.validate(self)
    }
}

enum TeamAuditPayloadURLValidator {
    static func validate(_ payload: TeamAuditPayload) throws {
        // 1. Mandatory artifact URLs
        for artifact in payload.artifacts where artifact.requirement == .mandatory {
            guard let urlStr = artifact.url, URLPolicy.validate(urlStr) != nil else {
                throw XPCError(
                    code: "schema.payload_decode_failed",
                    message: "Mandatory artifact missing or unsafe URL",
                    field: "artifacts.url"
                )
            }
        }

        // 2. Full report URL in overview
        if let fullReport = payload.overview?.publicationCoverage?.fullReport {
            if let urlStr = fullReport.url {
                guard URLPolicy.validate(urlStr) != nil else {
                    throw XPCError(
                        code: "schema.payload_decode_failed",
                        message: "Full report URL is unsafe",
                        field: "overview.publicationCoverage.fullReport.url"
                    )
                }
            }
        }

        // 3. Feedback lineage PR URL (when present)
        for lineage in payload.feedbackLineage {
            if let prURL = lineage.prURL {
                guard URLPolicy.validate(prURL) != nil else {
                    throw XPCError(
                        code: "schema.payload_decode_failed",
                        message: "Feedback lineage prURL is unsafe",
                        field: "feedbackLineage.prURL"
                    )
                }
            }
        }
    }
}
