import ArgumentParser
import Foundation

@main
struct AIDashCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aidash",
        abstract: "AIDash CLI — manage briefings, containers, cards, and events via XPC.",
        version: "1.0.0",
        subcommands: [
            BriefingCommand.self,
            ContainerCommand.self,
            CardCommand.self,
            EventsCommand.self,
            SchemaCommand.self,
        ]
    )
}

// MARK: - Briefing

struct BriefingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "briefing",
        abstract: "Manage briefings.",
        subcommands: [
            BriefingPutCommand.self,
            BriefingPublishCommand.self,
            BriefingGetCommand.self,
        ]
    )
}

struct BriefingPublishCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish",
        abstract: "Mark a briefing as published."
    )

    func run() async throws {
        fatalError("not yet implemented in T051")
    }
}

struct BriefingGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Read a briefing."
    )

    func run() async throws {
        fatalError("not yet implemented in T052")
    }
}

// MARK: - Container

struct ContainerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "container",
        abstract: "Manage containers.",
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
        abstract: "Delete a container."
    )

    func run() async throws {
        fatalError("not yet implemented in T053")
    }
}

// MARK: - Card

struct CardCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "card",
        abstract: "Manage cards.",
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
        fatalError("not yet implemented in T054")
    }
}

// MARK: - Events

struct EventsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "events",
        abstract: "Manage user events.",
        subcommands: [
            EventsPullCommand.self,
        ]
    )
}

struct EventsPullCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Pull user events."
    )

    func run() async throws {
        fatalError("not yet implemented in T055")
    }
}

// MARK: - Schema

struct SchemaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Inspect schema.",
        subcommands: [
            SchemaListCommand.self,
        ]
    )
}

struct SchemaListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the full schema."
    )

    func run() async throws {
        fatalError("not yet implemented in T055")
    }
}
