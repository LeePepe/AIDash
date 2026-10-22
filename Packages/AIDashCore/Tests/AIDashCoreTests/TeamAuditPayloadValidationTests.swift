import Foundation
import Testing
@testable import AIDashCore

@Suite("TeamAuditPayload Validation Tests")
struct TeamAuditPayloadValidationTests {

    private let sampleSHA = String(repeating: "a", count: 64)
    private let sidecarSHA = String(repeating: "b", count: 64)

    @Test func mandatoryArtifactMissingURLThrows() {
        let artifact = ArtifactManifestEntry(
            artifactID: "art-1",
            snapshotID: "snap-1",
            kind: .genericWorkflow,
            title: "Workflow",
            contentSHA256: sampleSHA,
            url: nil,
            requirement: .mandatory,
            sidecarID: "sidecar-1",
            sidecarSHA256: sidecarSHA
        )
        let catalog = SnapshotReferenceCatalog(
            artifacts: [ArtifactReference(artifactID: "art-1", kind: .genericWorkflow, contentSHA256: sampleSHA, sidecarID: "sidecar-1", sidecarSHA256: sidecarSHA)]
        )
        let payload = TeamAuditPayload(
            snapshotID: "snap-1",
            capturedAt: Date(),
            scope: AuditScope(owner: "Owner"),
            mode: .baseline,
            section: .artifacts,
            partIndex: 0,
            partCount: 1,
            contentSHA256: sampleSHA,
            artifactSidecarID: "sidecar-1",
            artifactSidecarSHA256: sidecarSHA,
            referenceCatalog: catalog,
            artifacts: [artifact]
        )
        #expect(throws: XPCError.self) {
            try payload.validateInvariants()
        }
    }

    @Test func mandatoryArtifactInsecureURLThrows() {
        let artifact = ArtifactManifestEntry(
            artifactID: "art-1",
            snapshotID: "snap-1",
            kind: .genericWorkflow,
            title: "Workflow",
            contentSHA256: sampleSHA,
            url: "http://example.com/art",
            requirement: .mandatory,
            sidecarID: "sidecar-1",
            sidecarSHA256: sidecarSHA
        )
        let catalog = SnapshotReferenceCatalog(
            artifacts: [ArtifactReference(artifactID: "art-1", kind: .genericWorkflow, contentSHA256: sampleSHA, url: "http://example.com/art", sidecarID: "sidecar-1", sidecarSHA256: sidecarSHA)]
        )
        let payload = TeamAuditPayload(
            snapshotID: "snap-1",
            capturedAt: Date(),
            scope: AuditScope(owner: "Owner"),
            mode: .baseline,
            section: .artifacts,
            partIndex: 0,
            partCount: 1,
            contentSHA256: sampleSHA,
            artifactSidecarID: "sidecar-1",
            artifactSidecarSHA256: sidecarSHA,
            referenceCatalog: catalog,
            artifacts: [artifact]
        )
        #expect(throws: XPCError.self) {
            try payload.validateInvariants()
        }
    }

    @Test func optionalArtifactInsecureURLAccepted() throws {
        let artifact = ArtifactManifestEntry(
            artifactID: "art-1",
            snapshotID: "snap-1",
            kind: .genericWorkflow,
            title: "Workflow",
            contentSHA256: sampleSHA,
            url: "http://example.com/optional",
            requirement: .optional,
            sidecarID: "sidecar-1",
            sidecarSHA256: sidecarSHA
        )
        let catalog = SnapshotReferenceCatalog(
            artifacts: [ArtifactReference(artifactID: "art-1", kind: .genericWorkflow, contentSHA256: sampleSHA, url: "http://example.com/optional", sidecarID: "sidecar-1", sidecarSHA256: sidecarSHA)]
        )
        let payload = TeamAuditPayload(
            snapshotID: "snap-1",
            capturedAt: Date(),
            scope: AuditScope(owner: "Owner"),
            mode: .baseline,
            section: .artifacts,
            partIndex: 0,
            partCount: 1,
            contentSHA256: sampleSHA,
            artifactSidecarID: "sidecar-1",
            artifactSidecarSHA256: sidecarSHA,
            referenceCatalog: catalog,
            artifacts: [artifact]
        )
        try payload.validateInvariants()
    }
}
