import ArgumentParser
import Foundation

// MARK: - Container Group

/// `aidash container <subcommand>` — manage briefing containers.
struct Container: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "container",
        abstract: "Create, update, and delete containers.",
        subcommands: [
            Put.self,
            Delete.self,
        ]
    )

    // MARK: - container put

    struct Put: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "put",
            abstract: "Create or update a container."
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Briefing date (YYYY-MM-DD, 'today', or 'yesterday').")
        var briefingDate: String

        @Option(name: .long, help: "Container UUID.")
        var id: String

        @Option(name: .long, help: "Container heading.")
        var title: String

        @Option(name: .long, help: "Optional secondary heading.")
        var subtitle: String?

        @Option(name: .long, help: "Display order (sparse int).")
        var order: Int

        @Option(name: .long, help: "Layout hint: auto, list, grid, hero.")
        var layout: String?

        @Option(name: .long, help: "Visual style: neutral, success, warning, accent.")
        var style: String?

        func run() async throws {
            throw NotImplementedError(task: "T053")
        }
    }

    // MARK: - container delete

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a container and its child cards."
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Container UUID to delete.")
        var id: String

        func run() async throws {
            throw NotImplementedError(task: "T053")
        }
    }
}
