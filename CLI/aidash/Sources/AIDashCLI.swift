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

    @Flag(name: .long, help: "Emit machine-readable JSON on stdout instead of human format.")
    var json = false

    @Flag(name: .long, help: "Suppress non-essential stdout (errors still go to stderr).")
    var quiet = false

    // MARK: - Global error handler (T044)

    static func main() async {
        do {
            var command = try parseAsRoot()
            if var asyncCmd = command as? AsyncParsableCommand {
                try await asyncCmd.run()
            } else {
                try command.run()
            }
        } catch let xpcError as XPCError {
            // XPC-layer or domain errors → emit JSON envelope and exit with mapped code
            try? JSONOutput().emit(error: xpcError)
            Darwin.exit(ExitCodeMapper.code(for: xpcError))
        } catch {
            // ArgumentParser routes `--help` / `--version` here as "errors" with
            // exit code `.success`; those must print to stdout (or stderr per
            // ArgumentParser) and exit 0 — they are NOT contract errors. For
            // everything else (parser errors, validation failures, unknown
            // errors), the CLI contract requires a JSON envelope on stderr with
            // a mapped exit code.
            let argParserExit = Self.exitCode(for: error)
            if argParserExit == ExitCode.success {
                // Let ArgumentParser handle help/version output and exit 0.
                Self.exit(withError: error)
            }
            let wrapped = XPCError(
                code: "schema.invalid_argument",
                message: Self.fullMessage(for: error),
                field: nil,
                got: nil,
                allowed: nil
            )
            try? JSONOutput().emit(error: wrapped)
            Darwin.exit(ExitCodeMapper.code(for: wrapped))
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
        fatalError("not yet implemented in T050")
    }
}

struct BriefingPublishCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Mark a briefing as visible to readers."
    )

    func run() async throws {
        fatalError("not yet implemented in T051")
    }
}

struct BriefingGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Read a briefing (containers + cards)."
    )

    func run() async throws {
        fatalError("not yet implemented in T052")
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
        fatalError("not yet implemented in T053")
    }
}

struct ContainerDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a container and its child cards."
    )

    func run() async throws {
        fatalError("not yet implemented in T175")
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

struct CardPutCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "put",
        abstract: "Create or update a card."
    )

    func run() async throws {
        fatalError("not yet implemented in T054")
    }
}

struct CardDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a card."
    )

    func run() async throws {
        fatalError("not yet implemented in T176")
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
        fatalError("not yet implemented in T170")
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

struct SchemaListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Print the full schema as JSON."
    )

    func run() async throws {
        fatalError("not yet implemented in T055")
    }
}
