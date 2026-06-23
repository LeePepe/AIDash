# Data Model: Core Briefing & CLI

> Phase 1 artifact of `/speckit-plan`. Defines all SwiftData `@Model`
> classes, Codable structs, enums, and the data shape passed through XPC
> and persisted in CloudKit.

---

## Layer overview

```
┌───────────────────────────────────────────────────────────┐
│ AIDashCore/Models/        ← schema source of truth         │
│   Codable structs:                                         │
│     Briefing, Container, Card,                             │
│     MetricPayload, InsightPayload, ... (per CardType)      │
│     UserEvent                                              │
│   Enums:                                                   │
│     CardType, CardSize, CardStyle, ContainerLayout,        │
│     UserEventAction                                        │
└───────────────────────────────────────────────────────────┘
                    │
                    │ encode/decode via Codable
                    ▼
┌───────────────────────────────────────────────────────────┐
│ AIDashCore/Storage/       ← SwiftData @Model classes       │
│   BriefingModel, ContainerModel, CardModel, UserEventModel │
│   (mirror the Codable structs, store payloads as Data)     │
└───────────────────────────────────────────────────────────┘
                    │
                    │ NSPersistentCloudKitContainer
                    ▼
┌───────────────────────────────────────────────────────────┐
│ iCloud Private DB         ← actual storage                 │
│   Record types auto-generated from @Model classes          │
└───────────────────────────────────────────────────────────┘
```

---

## Enums (CardType, CardSize, CardStyle, ContainerLayout, UserEventAction)

All `Codable, Sendable, CaseIterable, RawRepresentable<String>`. Defined
in `AIDashCore/Models/`. Validation logic in
`AIDashCore/Validation/SchemaValidator.swift`.

```swift
public enum CardType: String, Codable, Sendable, CaseIterable {
    case metric
    case insight
    case agentSummary
    case todoList
    case trending
    case digest
    case sectionHeader
}

public enum CardSize: String, Codable, Sendable, CaseIterable {
    case small, medium, wide, hero
}

public enum CardStyle: String, Codable, Sendable, CaseIterable {
    case neutral, success, warning, accent
}

public enum ContainerLayout: String, Codable, Sendable, CaseIterable {
    case auto, list, grid, hero
}

public enum UserEventAction: String, Codable, Sendable, CaseIterable {
    case done, star
    // `hide` deferred to v2 per spec D17
}
```

**Validation rules** (enforced by `SchemaValidator`):
- All fields received from CLI must `init(rawValue:)` cleanly.
- `payloadJSON.count <= 256 * 1024` (256 KB hard limit, well below
  CloudKit's 1 MB per-record limit).

---

## Codable structs (the schema source of truth)

### Briefing

```swift
public struct Briefing: Codable, Sendable {
    public let date: String           // "YYYY-MM-DD"
    public let generatedAt: Date
    public let generatedBy: String    // human-readable agent name
    public let containers: [Container]
}
```

### Container

```swift
public struct Container: Codable, Sendable {
    public let id: String             // caller-supplied UUID
    public let title: String          // agent-chosen
    public let subtitle: String?
    public let order: Int             // sparse: 10, 20, 30 ...
    public let layout: ContainerLayout
    public let style: CardStyle       // reused enum
    public let cards: [Card]
}
```

### Card

```swift
public struct Card: Codable, Sendable {
    public let id: String             // caller-supplied UUID
    public let type: CardType
    public let size: CardSize
    public let style: CardStyle
    public let payload: Data          // JSON-encoded per-type payload
}
```

### UserEvent

```swift
public struct UserEvent: Codable, Sendable {
    public let id: String             // device-generated UUID
    public let timestamp: Date
    public let device: String         // "Tianpli 的 iPhone [3F2A4B1C]"
    public let cardId: String
    public let action: UserEventAction
}
```

### Per-CardType payload structs

Each CardType has exactly one strongly-typed payload struct. These are the
**only place** where each card's field schema is defined.

```swift
public struct MetricPayload: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public let label: String      // "Tasks completed"
        public let value: Double
        public let unit: String?      // "ms", "%", "$"
        public let trend: Trend?      // up | down | flat
        public enum Trend: String, Codable, Sendable { case up, down, flat }
    }
    public let items: [Item]
}

public struct InsightPayload: Codable, Sendable {
    public struct Citation: Codable, Sendable {
        public let label: String
        public let url: String        // arbitrary scheme; not validated
    }
    public let title: String
    public let body: String
    public let citations: [Citation]?
}

public struct AgentSummaryPayload: Codable, Sendable {
    public struct Completed: Codable, Sendable {
        public let title: String
        public let ref: String?       // PR URL, issue ID, etc.
    }
    public struct Stat: Codable, Sendable {
        public let label: String      // "Lines of code", "PRs merged"
        public let value: Double
    }
    public let agentName: String      // "claude-code", "multica/sapphire"
    public let completed: [Completed]
    public let stats: [Stat]?
}

public struct TodoListPayload: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public let title: String
        public let priority: Priority?
        public let due: Date?
        public let ref: String?
        public enum Priority: String, Codable, Sendable { case low, medium, high }
    }
    public let items: [Item]
}

public struct TrendingPayload: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public let title: String
        public let url: String
        public let score: Double?     // optional sort key
    }
    public let topic: String          // "AI news", "Crypto", ...
    public let items: [Item]
}

public struct DigestPayload: Codable, Sendable {
    public struct Section: Codable, Sendable {
        public let heading: String
        public let paragraphs: [String]
    }
    public let title: String
    public let body: String           // primary content (may be the only field used)
    public let sections: [Section]?   // optional structured breakdown
}

public struct SectionHeaderPayload: Codable, Sendable {
    public let title: String
    public let subtitle: String?
}
```

### CardType → payload dispatch

```swift
public protocol CardPayloadProtocol: Codable, Sendable {}
extension MetricPayload: CardPayloadProtocol {}
extension InsightPayload: CardPayloadProtocol {}
extension AgentSummaryPayload: CardPayloadProtocol {}
extension TodoListPayload: CardPayloadProtocol {}
extension TrendingPayload: CardPayloadProtocol {}
extension DigestPayload: CardPayloadProtocol {}
extension SectionHeaderPayload: CardPayloadProtocol {}

extension CardType {
    public func decode(_ data: Data) throws -> any CardPayloadProtocol {
        let decoder = JSONDecoder()
        switch self {
        case .metric:        return try decoder.decode(MetricPayload.self, from: data)
        case .insight:       return try decoder.decode(InsightPayload.self, from: data)
        case .agentSummary:  return try decoder.decode(AgentSummaryPayload.self, from: data)
        case .todoList:      return try decoder.decode(TodoListPayload.self, from: data)
        case .trending:      return try decoder.decode(TrendingPayload.self, from: data)
        case .digest:        return try decoder.decode(DigestPayload.self, from: data)
        case .sectionHeader: return try decoder.decode(SectionHeaderPayload.self, from: data)
        }
    }

    public func validate(_ data: Data) throws {
        _ = try decode(data)   // throws on schema violation; caller maps to XPCError
    }
}
```

---

## SwiftData `@Model` classes (storage mirror)

These mirror the Codable structs but use SwiftData persistence semantics
(`@Attribute(.unique)`, `@Relationship`, default values for migration).

```swift
import SwiftData

@Model
public final class BriefingModel {
    @Attribute(.unique) public var date: String              // "2026-06-23"
    public var generatedAt: Date
    public var generatedBy: String
    @Relationship(deleteRule: .cascade, inverse: \ContainerModel.briefing)
    public var containers: [ContainerModel]

    public init(date: String, generatedAt: Date, generatedBy: String) {
        self.date = date
        self.generatedAt = generatedAt
        self.generatedBy = generatedBy
        self.containers = []
    }
}

@Model
public final class ContainerModel {
    @Attribute(.unique) public var id: String                // UUID from agent
    public var title: String
    public var subtitle: String?
    public var order: Int
    public var layoutRaw: String                             // ContainerLayout.rawValue
    public var styleRaw: String                              // CardStyle.rawValue
    @Relationship(deleteRule: .cascade, inverse: \CardModel.container)
    public var cards: [CardModel]
    public var briefing: BriefingModel?                      // inverse for cascade

    public init(id: String, title: String, subtitle: String?, order: Int,
                layout: ContainerLayout, style: CardStyle) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.order = order
        self.layoutRaw = layout.rawValue
        self.styleRaw = style.rawValue
        self.cards = []
    }

    public var layout: ContainerLayout {
        get { ContainerLayout(rawValue: layoutRaw) ?? .auto }
        set { layoutRaw = newValue.rawValue }
    }
    public var style: CardStyle {
        get { CardStyle(rawValue: styleRaw) ?? .neutral }
        set { styleRaw = newValue.rawValue }
    }
}

@Model
public final class CardModel {
    @Attribute(.unique) public var id: String                // UUID from agent
    public var typeRaw: String                                // CardType.rawValue
    public var sizeRaw: String
    public var styleRaw: String
    public var payloadJSON: Data
    public var container: ContainerModel?                    // inverse for cascade

    public init(id: String, type: CardType, size: CardSize,
                style: CardStyle, payloadJSON: Data) {
        self.id = id
        self.typeRaw = type.rawValue
        self.sizeRaw = size.rawValue
        self.styleRaw = style.rawValue
        self.payloadJSON = payloadJSON
    }

    public var type: CardType { CardType(rawValue: typeRaw)! }
    public var size: CardSize { CardSize(rawValue: sizeRaw)! }
    public var style: CardStyle { CardStyle(rawValue: styleRaw)! }
}

@Model
public final class UserEventModel {
    @Attribute(.unique) public var id: String
    public var timestamp: Date
    public var device: String
    public var cardId: String
    public var actionRaw: String

    public init(id: String, timestamp: Date, device: String,
                cardId: String, action: UserEventAction) {
        self.id = id
        self.timestamp = timestamp
        self.device = device
        self.cardId = cardId
        self.actionRaw = action.rawValue
    }

    public var action: UserEventAction { UserEventAction(rawValue: actionRaw)! }
}
```

### Why rawValue storage for enums

SwiftData supports `enum: String` natively, but storing `String` directly
and exposing a typed computed property gives:
- Cleaner CloudKit record fields (`String` value, not `Int` ordinal that
  changes if enum is reordered).
- Forward compat: unknown enum values become "no, that's not a real
  CardType" at read time, not a parse crash.

---

## ModelContainer configuration (app target only)

```swift
import SwiftData

@MainActor
enum DataStore {
    static let shared: ModelContainer = {
        let schema = Schema([
            BriefingModel.self,
            ContainerModel.self,
            CardModel.self,
            UserEventModel.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private("iCloud.com.tianpli.aidash")
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Constitution: no fatalError. Surface to UI as actionable state.
            fatalError("ModelContainer init failed: \(error)")
            // Implementation TODO: replace with a graceful error scene
        }
    }()
}
```

> **Implementation note**: the `fatalError` above is a placeholder. The
> real implementation must show a "Storage unavailable" UI scene per spec
> FR-041. Tracked in tasks phase.

---

## Indexes and query patterns

| Query | Pattern | Notes |
|---|---|---|
| "Today's briefing" | `#Predicate<BriefingModel> { $0.date == today }` | Unique attribute → 1 result |
| "Most recent published" | sort by `date` desc, limit 1 | Fallback when today is empty |
| "Cards in container, ordered" | from `ContainerModel.cards` | SwiftData preserves relationship order |
| "Events since T" | `#Predicate<UserEventModel> { $0.timestamp >= since }` sorted by timestamp asc | CLI `events pull` |
| "Old briefings to delete" | `#Predicate<BriefingModel> { $0.date < cutoff }` | Background cleanup task |

---

## Idempotency contract

The CLI subcommands `put` are idempotent by `id`:
- `briefing put` with the same `date` updates `generatedAt` and
  `generatedBy`, leaves containers alone (those have their own put).
- `container put` with the same `id` replaces `title/subtitle/order/layout/
  style`, leaves cards alone (those have their own put).
- `card put` with the same `id` replaces `type/size/style/payload`.

`publish` is a metadata-only marker (sets a `publishedAt` field on
BriefingModel — extending the schema slightly compared to the bare struct
above). When the app's SwiftUI observer sees `publishedAt != nil`, the
briefing becomes visible. This is how spec FR-006's atomic publish works.

Add to BriefingModel:
```swift
public var publishedAt: Date?    // nil until `briefing publish` called
```

---

## Schema versioning

Schema version is implicit (per-struct). Migration strategy:

- **Adding a non-required field** to any Codable payload: zero migration —
  JSONDecoder accepts the new field; old records lacking it produce a
  default value (the property must be `?` or have a default).
- **Adding a new CardType**: zero data migration; existing records keep
  working. CLI version bump + App version bump must both ship before
  agents use the new type.
- **Renaming a field** (rare): use a 2-step migration: add new field
  alongside old, dual-write for one app release, drop old field in the
  next release.
- **Removing a CardType** (very rare): mark as deprecated for one
  release (CLI rejects new use; existing records still render), then
  remove the case in the next release.

SwiftData migration (rarely needed since we use rawValue strings, not
typed enums in storage): use the `VersionedSchema` + `SchemaMigrationPlan`
pattern when @Model class shape changes.
