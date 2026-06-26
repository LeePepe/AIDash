import ArgumentParser
import AIDashCore
import Foundation

@main
struct AIDash: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aidash",
        abstract: "AIDash CLI — publish briefings, query schema, pull events.",
        version: "1.0.0",
        subcommands: [
            BriefingCommand.self,
            ContainerCommand.self,
            CardCommand.self,
            EventsCommand.self,
            SchemaCommand.self,
        ]
    )

    // MARK: - Root-level global flags
    //
    // Declared on the root command so `parseAsRoot()` accepts
    // `aidash --json briefing publish ...` and `aidash --quiet ...`.
    // Leaf commands also expose them via `GlobalOptions` (via OptionGroup)
    // so the same flags work after the subcommand verb. `GlobalOptions`
    // additionally inspects `ProcessInfo.processInfo.arguments` so that the
    // effective flags can be observed from any leaf regardless of position.

    @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of human format.")
    var json: Bool = false

    @Flag(name: .long, help: "Suppress non-essential stdout (errors still go to stderr).")
    var quiet: Bool = false

    // MARK: - Global error handler

    static func main() async {
        do {
            var command = try parseAsRoot()
            if var asyncCmd = command as? any AsyncParsableCommand {
                try await asyncCmd.run()
            } else {
                try command.run()
            }
            Darwin.exit(0)
        } catch let xpcError as XPCError {
            try? JSONOutput().emit(error: xpcError)
            Darwin.exit(ExitCodeMapper.code(for: xpcError))
        } catch {
            // Determine if this is a clean exit (--help, --version) or a
            // validation failure (missing required flags, unknown args).
            let code = exitCode(for: error)
            if code == .success {
                // --help / --version: ArgumentParser formats its own output
                Self.exit(withError: error)
            } else {
                // Validation failure → structured JSON envelope on stderr, exit 1
                let wrapped = XPCError(
                    code: "schema.argument_validation_failed",
                    message: Self.message(for: error)
                )
                try? JSONOutput().emit(error: wrapped)
                Darwin.exit(1)
            }
        }
    }
}

// MARK: - Briefing

struct BriefingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "briefing",
        abstract: "Manage daily briefings.",
        subcommands: [
            BriefingPutCommand.self,
            BriefingPublishCommand.self,
            BriefingGetCommand.self,
        ]
    )
}

struct BriefingPutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "put",
        abstract: "Create or update a briefing's top-level metadata."
    )

    func run() async throws {
        throw XPCError(
            code: "internal.not_implemented",
            message: "briefing put is not yet implemented (T050)"
        )
    }
}

struct BriefingGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Read a briefing (containers + cards)."
    )

    func run() async throws {
        throw XPCError(
            code: "internal.not_implemented",
            message: "briefing get is not yet implemented (T052)"
        )
    }
}

// MARK: - Container

struct ContainerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "container",
        abstract: "Manage briefing containers.",
        subcommands: [
            ContainerPutCommand.self,
            ContainerDeleteCommand.self,
        ]
    )
}

struct ContainerPutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "put",
        abstract: "Create or update a container."
    )

    func run() async throws {
        throw XPCError(
            code: "internal.not_implemented",
            message: "container put is not yet implemented (T053)"
        )
    }
}

struct ContainerDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a container and its child cards."
    )

    func run() async throws {
        throw XPCError(
            code: "internal.not_implemented",
            message: "container delete is not yet implemented (T175)"
        )
    }
}

// MARK: - Card

struct CardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "card",
        abstract: "Manage cards within containers.",
        subcommands: [
            CardPutCommand.self,
            CardDeleteCommand.self,
        ]
    )
}

// `CardPutCommand` is defined in `Commands/CardPutCommand.swift` (T054).

struct CardDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a card."
    )

    func run() async throws {
        throw XPCError(
            code: "internal.not_implemented",
            message: "card delete is not yet implemented (T176)"
        )
    }
}

// MARK: - Events

struct EventsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "Query user interaction events.",
        subcommands: [
            EventsPullCommand.self,
        ]
    )
}

struct EventsPullCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Pull user events since a given timestamp."
    )

    func run() async throws {
        throw XPCError(
            code: "internal.not_implemented",
            message: "events pull is not yet implemented (T170)"
        )
    }
}

// MARK: - Schema

struct SchemaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Query the AIDash schema.",
        subcommands: [
            SchemaListCommand.self,
        ]
    )
}

// `SchemaListCommand` is defined in `Commands/SchemaListCommand.swift` (T055).
