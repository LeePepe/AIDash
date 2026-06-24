import SwiftData

/// Manages the CloudKit-backed SwiftData container initialization.
/// Full implementation arrives in T070; this provides the InitState contract.
public enum CloudKitContainer {

    /// The result of attempting to initialize the CloudKit-backed ModelContainer.
    public enum InitState: Sendable {
        /// Container is ready for use.
        case ready(ModelContainer)
        /// Initialization failed with a human-readable reason.
        case failed(String)
    }
}
