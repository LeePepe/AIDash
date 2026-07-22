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
    public let itemRef: String?       // optional; item-level ref within the card
}
```

**`itemRef` (added spec 002 D1 / T001, 2026-07-20)** — optional stable
identifier of the specific item within the card that the event targets. For a
`trending` radar card, this is the item's `url` (e.g. GitHub repo URL). Absent
(nil) for whole-card events (`.done`/`.star` on the whole card). Optional and
forward-compat: older records / older JSON without this key decode as nil (same
pattern used for `TrendingPayload.Item.delta` / `category` / `reason`). Core
provides a factory helper `UserEvent.star(cardId:itemRef:device:)` that mints a
fresh UUID and current timestamp for item-level star events.

**D2 decision (2026-07-20)** — star is a toggle but stays **append-only**. v1
emits only `.star` events; the UI derives the current filled state from
"star events emitted by this account for this `(cardId, itemRef)` pair" (last
event wins on duplicates; agents dedupe by `itemRef+cardId`). No
`UserEventAction.unstar` case is added in v1; if a downstream enrichment
consumer later needs an explicit revoke signal, add it in a follow-up spec.
This satisfies constitution principle I (events are append-only, never
deleted or mutated).

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

These mirror the Codable structs but use SwiftData persistence semantics.

> **CloudKit compatibility (MY-1016 / MY-1018)** — when the SwiftData store is
> backed by `NSPersistentCloudKitContainer`, CloudKit imposes three
> non-negotiable schema constraints on every `@Model` class:
>
> 1. Every stored scalar attribute must be **optional** or have a **default
>    value**. Non-optional/no-default scalars cause `Store failed to load`
>    at app launch.
> 2. Every to-many relationship must be **optional**. CloudKit cannot model
>    a non-optional `[Child]` to-many; the underlying record field is
>    nullable. Business code MUST treat `nil` as "empty array".
> 3. `@Attribute(.unique)` is **forbidden** — CloudKit has no uniqueness
>    enforcement. Logical uniqueness (briefing by `date`, container/card by
>    `id`) is enforced in the **XPC business layer** (`XPCHandlers`) by
>    fetching by logical key first and updating in place, otherwise
>    inserting.
>
> The Codable wire structs (`Briefing`, `Container`, `Card`, `UserEvent` and
> the per-CardType payloads) keep their required, non-optional fields —
> the CLI contract is unchanged. Only the SwiftData storage mirror is
> relaxed for CloudKit.

```swift
import SwiftData

@Model
public final class BriefingModel {
    public var date: String = ""              // "2026-06-23" — required by validator
    public var generatedAt: Date = Date.distantPast
    public var generatedBy: String = ""
    public var publishedAt: Date?             // nil until briefing.publish
    @Relationship(deleteRule: .cascade, inverse: \ContainerModel.briefing)
    var rawContainers: [ContainerModel]?       // CloudKit-nullable to-many

    public init(date: String, generatedAt: Date, generatedBy: String, publishedAt: Date? = nil) {
        self.date = date
        self.generatedAt = generatedAt
        self.generatedBy = generatedBy
        self.publishedAt = publishedAt
        self.rawContainers = []
    }

    /// Business-layer view: nil is treated as empty.
    public var containers: [ContainerModel] {
        get { rawContainers ?? [] }
        set { rawContainers = newValue }
    }
}

@Model
public final class ContainerModel {
    public var id: String = ""                // UUID from agent
    public var title: String = ""
    public var subtitle: String?
    public var order: Int = 0
    public var layoutRaw: String = ContainerLayout.auto.rawValue
    public var styleRaw: String = CardStyle.neutral.rawValue
    @Relationship(deleteRule: .cascade, inverse: \CardModel.container)
    var rawCards: [CardModel]?
    public var briefing: BriefingModel?       // inverse for cascade

    public init(id: String, title: String, subtitle: String?, order: Int,
                layout: ContainerLayout, style: CardStyle) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.order = order
        self.layoutRaw = layout.rawValue
        self.styleRaw = style.rawValue
        self.rawCards = []
    }

    public var layout: ContainerLayout {
        get { ContainerLayout(rawValue: layoutRaw) ?? .auto }
        set { layoutRaw = newValue.rawValue }
    }
    public var style: CardStyle {
        get { CardStyle(rawValue: styleRaw) ?? .neutral }
        set { styleRaw = newValue.rawValue }
    }
    public var cards: [CardModel] {
        get { rawCards ?? [] }
        set { rawCards = newValue }
    }
}

@Model
public final class CardModel {
    public var id: String = ""                // UUID from agent
    public var typeRaw: String = CardType.metric.rawValue
    public var sizeRaw: String = CardSize.medium.rawValue
    public var styleRaw: String = CardStyle.neutral.rawValue
    public var payloadJSON: Data = Data()
    public var container: ContainerModel?     // inverse for cascade

    public init(id: String, type: CardType, size: CardSize,
                style: CardStyle, payloadJSON: Data) {
        self.id = id
        self.typeRaw = type.rawValue
        self.sizeRaw = size.rawValue
        self.styleRaw = style.rawValue
        self.payloadJSON = payloadJSON
    }

    public var type: CardType {
        get { CardType(rawValue: typeRaw) ?? .metric }
        set { typeRaw = newValue.rawValue }
    }
    public var size: CardSize {
        get { CardSize(rawValue: sizeRaw) ?? .medium }
        set { sizeRaw = newValue.rawValue }
    }
    public var style: CardStyle {
        get { CardStyle(rawValue: styleRaw) ?? .neutral }
        set { styleRaw = newValue.rawValue }
    }
}

@Model
public final class UserEventModel {
    public var id: String = ""
    public var timestamp: Date = Date.distantPast
    public var device: String = ""
    public var cardId: String = ""
    public var actionRaw: String = UserEventAction.done.rawValue
    public var itemRef: String? = nil     // added spec 002 D1 (T001)

    public init(id: String, timestamp: Date, device: String,
                cardId: String, action: UserEventAction, itemRef: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.device = device
        self.cardId = cardId
        self.actionRaw = action.rawValue
        self.itemRef = itemRef
    }

    public var action: UserEventAction? { UserEventAction(rawValue: actionRaw) }
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
| "Today's briefing" | `#Predicate<BriefingModel> { $0.date == today }` | One result after dedupe — XPC handler fetches by date and updates in place |
| "Most recent published" | sort by `date` desc, limit 1 | Fallback when today is empty |
| "Cards in container, ordered" | from `ContainerModel.cards` (nil → empty) | SwiftData preserves relationship order |
| "Events since T" | `#Predicate<UserEventModel> { $0.timestamp >= since }` sorted by timestamp asc | CLI `events pull` |
| "Old briefings to delete" | `#Predicate<BriefingModel> { $0.date < cutoff }` | Background cleanup task |

---

## Idempotency contract

The CLI subcommands `put` are idempotent by `id`. Logical uniqueness is
enforced in the XPC business layer (`XPCHandlers`) — **not** by SwiftData
`@Attribute(.unique)`, which is incompatible with CloudKit. Each `put`
handler fetches by the logical key first; if a record exists it is updated
in place, otherwise a new record is inserted:

- `briefing put` fetches `BriefingModel` by `date`. Same date → update
  `generatedAt` / `generatedBy` (and set `publishedAt = now` when
  `published` is requested and not already set); leaves containers alone
  (those have their own put).
- `container put` fetches `ContainerModel` by `id` scoped to the
  requested parent briefing. Same `(briefingDate, id)` → replace
  `title/subtitle/order/layout/style`; a same-`id` container under a
  different briefing is rejected rather than silently moved. Leaves
  cards alone (those have their own put).
- `card put` fetches `CardModel` by `id` scoped to the requested parent
  container. Same `(containerId, id)` → replace `type/size/style/payload`;
  a same-`id` card under a different container is rejected.
- `events pull` reads `UserEventModel` ordered by `timestamp`; event id
  uniqueness is the device/agent's responsibility (UUID generated at
  source).

`publish` is a metadata-only marker (sets `publishedAt` on
`BriefingModel`). When the app's SwiftUI observer sees `publishedAt != nil`,
the briefing becomes visible. This is how spec FR-006's atomic publish
works.

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
