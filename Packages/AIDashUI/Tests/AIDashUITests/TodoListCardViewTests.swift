import Testing
import SwiftUI
import AIDashCore
@testable import AIDashUI

@MainActor
@Suite("TodoListCardView Tests")
struct TodoListCardViewTests {
    private let sampleItems: [TodoListPayload.Item] = [
        .init(title: "High priority task", priority: .high),
        .init(title: "Medium priority task", priority: .medium, due: Date()),
        .init(title: "Low priority task", priority: .low),
        .init(title: "No priority task"),
    ]

    @Test("initializes with correct payload, size, and style")
    func initializesCorrectly() {
        let payload = TodoListPayload(items: sampleItems)
        let view = TodoListCardView(payload: payload, size: .medium, style: .accent)

        #expect(view.payload.items.count == 4)
        #expect(view.size == .medium)
        #expect(view.style == .accent)
    }

    @Test("accepts all card sizes", arguments: CardSize.allCases)
    func acceptsAllSizes(size: CardSize) {
        let payload = TodoListPayload(items: [.init(title: "Task", priority: .high)])
        let view = TodoListCardView(payload: payload, size: size, style: .neutral)

        #expect(view.size == size)
    }

    @Test("accepts all card styles", arguments: CardStyle.allCases)
    func acceptsAllStyles(style: CardStyle) {
        let payload = TodoListPayload(items: [.init(title: "Task", priority: .low)])
        let view = TodoListCardView(payload: payload, size: .wide, style: style)

        #expect(view.style == style)
    }

    @Test("preserves payload items")
    func preservesPayloadItems() {
        let payload = TodoListPayload(items: sampleItems)
        let view = TodoListCardView(payload: payload, size: .hero, style: .success)

        #expect(view.payload.items.count == 4)
        #expect(view.payload.items[0].title == "High priority task")
        #expect(view.payload.items[0].priority == .high)
        #expect(view.payload.items[2].priority == .low)
    }

    // MARK: - Token contract (MY-1054 / MY-1059)

    @Test("uses the shared todoList typography recipe")
    func usesSharedTypographyRecipe() {
        #expect(TodoListCardView.recipe.primary == AIDashTypography.detail(for: .todoList).primary)
        #expect(TodoListCardView.recipe.secondary == AIDashTypography.detail(for: .todoList).secondary)
        #expect(TodoListCardView.recipe.secondaryColor == AIDashTypography.detail(for: .todoList).secondaryColor)
    }

    @Test("typography recipe is invariant across sizes (size = geometry only)")
    func typographyInvariantAcrossSizes() {
        // The recipe is a static, so it is mechanically size-independent. This
        // test pins the invariant so a future per-size font branch fails here.
        for _ in CardSize.allCases {
            #expect(TodoListCardView.recipe.primary == AIDashTypography.detail(for: .todoList).primary)
            #expect(TodoListCardView.recipe.secondary == AIDashTypography.detail(for: .todoList).secondary)
        }
    }

    @Test("todoList renders its required leading icon badge (no sectionHeader exemption)")
    func rendersTypeBadge() {
        #expect(CardType.todoList.hasIconBadge)
        #expect(CardType.todoList.iconSymbol == "checklist")
        #expect(CardType.todoList.iconTint == .green)
    }

    @Test("body materializes for every (size, style) combination without crashing")
    func bodyMaterializes() {
        let payload = TodoListPayload(items: sampleItems)
        for size in CardSize.allCases {
            for style in CardStyle.allCases {
                let view = TodoListCardView(payload: payload, size: size, style: style)
                _ = view.body
            }
        }
    }

    // MARK: - Source-level guard against forbidden local chrome
    //
    // Pin that the renderer does not reintroduce a local rounded background
    // or a backgroundTint switch (§Quality Bar I P0.3). The test reads the
    // source file from the package and fails if either pattern is present.

    @Test("renderer source contains no local backgroundTint or RoundedRectangle chrome")
    func sourceHasNoLocalChrome() throws {
        let source = try loadRendererSource(named: "TodoListCardView")
        #expect(!source.contains("backgroundTint"), "TodoListCardView must not declare a local backgroundTint")
        #expect(!source.contains("RoundedRectangle(cornerRadius:"), "TodoListCardView must not draw its own rounded background")
        #expect(source.contains(".cardChrome(size: size, style: style)"), "TodoListCardView must consume the shared cardChrome modifier")
        #expect(source.contains("CardTypeBadge(type: .todoList)"), "TodoListCardView must render the shared 32×32 type badge")
    }
}

// MARK: - Source loader (used by chrome-guard tests)

/// Reads a `.swift` file from `Packages/AIDashUI/Sources/AIDashUI/CardView/`
/// regardless of build directory. We walk up from `#filePath` (the test
/// source location) until we hit the package root, then descend into
/// `Sources`. This works for `swift test`, `xcodebuild test`, and Xcode
/// indexer runs.
func loadRendererSource(named name: String, file: StaticString = #filePath) throws -> String {
    let here = URL(fileURLWithPath: String(describing: file))
    var dir = here.deletingLastPathComponent()
    while dir.lastPathComponent != "Tests" && dir.path != "/" {
        dir = dir.deletingLastPathComponent()
    }
    guard dir.lastPathComponent == "Tests" else {
        throw SourceLookupError.testsRootNotFound
    }
    let packageRoot = dir.deletingLastPathComponent()
    let renderer = packageRoot
        .appendingPathComponent("Sources")
        .appendingPathComponent("AIDashUI")
        .appendingPathComponent("CardView")
        .appendingPathComponent("\(name).swift")
    return try String(contentsOf: renderer, encoding: .utf8)
}

enum SourceLookupError: Error {
    case testsRootNotFound
}
