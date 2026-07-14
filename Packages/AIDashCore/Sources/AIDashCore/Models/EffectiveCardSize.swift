import Foundation

/// Resolves the *effective* geometry size a card should render at, given its
/// authored `size` and its payload's content richness.
///
/// ## Why
///
/// `size` is an authoring instruction, but publishers (a cron, an agent) often
/// pick a size larger than the content justifies — a one-line digest tagged
/// `hero`, a single-item to-do tagged `wide`. Because `size` drives BOTH grid
/// span (a `wide`/`hero` card fills the whole row) AND the min-height floor
/// (`hero` ≥ 280pt), such a card renders as a large, half-empty box.
///
/// This resolver treats the authored `size` as an **upper bound**: it computes
/// the largest size the payload actually *justifies* and returns the smaller of
/// (authored, justified). It only ever shrinks — an explicitly-`small` card
/// stays small — and it never mutates the stored card. Applying the same
/// effective size to both the grid span and the card's own geometry keeps width
/// and height coherent.
///
/// `metric`, `trending`, and `sectionHeader` are pass-through (their sizing is
/// deliberate): they always return the authored size unchanged.
public enum EffectiveCardSize {

    // MARK: - Thresholds (heuristic, downgrade-only, CJK-conservative)
    //
    // Character counts use `String.count` (grapheme clusters). CJK content is
    // denser per character than Latin, so these are intentionally conservative
    // — the resolver only ever SHRINKS, so a wrong guess yields a
    // slightly-too-small (or unchanged) card, never a broken layout. Tune here.

    /// digest: single prose body long enough to fill a full-row `wide`.
    private static let digestBodyWide = 400
    /// digest: body long enough for a 2-column `medium`.
    private static let digestBodyMedium = 160
    /// insight: body long enough to justify `hero` alongside citations.
    private static let insightBodyHero = 240
    /// insight: body long enough for a full-row `wide` without citations.
    private static let insightBodyWide = 220
    /// insight: body long enough for a `medium`.
    private static let insightBodyMedium = 90

    // MARK: - Resolve

    /// Effective size from an undecoded payload. Decodes once; on failure
    /// returns `authored` unchanged (a card that can't decode renders the
    /// router fallback and must keep its authored geometry).
    public static func resolve(
        type: CardType,
        authored: CardSize,
        payloadJSON: Data,
        collapseToList: Bool = false
    ) -> CardSize {
        let payload = try? type.decode(payloadJSON)
        return resolve(
            type: type,
            authored: authored,
            payload: payload,
            collapseToList: collapseToList
        )
    }

    /// Effective size from an already-decoded payload (avoids a second decode
    /// for callers that have the payload in hand).
    public static func resolve(
        type: CardType,
        authored: CardSize,
        payload: (any CardPayloadProtocol)?,
        collapseToList: Bool
    ) -> CardSize {
        // ListLayout forces every card to span the full row; a downgrade there
        // is meaningless and would fight `collapseToList`.
        guard !collapseToList else { return authored }

        guard let justified = justifiedSize(type: type, payload: payload) else {
            // Pass-through type, or a payload that didn't decode → no downgrade.
            return authored
        }

        // Downgrade only: never return larger than authored.
        return rank(justified) < rank(authored) ? justified : authored
    }

    // MARK: - Per-type justification

    /// The largest size the payload's richness justifies, or `nil` for
    /// pass-through types (metric / trending / sectionHeader) and undecoded
    /// payloads — both meaning "leave the authored size alone".
    private static func justifiedSize(
        type: CardType,
        payload: (any CardPayloadProtocol)?
    ) -> CardSize? {
        switch type {
        case .metric, .trending, .sectionHeader:
            return nil // deliberate sizing — never downgrade

        case .digest:
            guard let p = payload as? DigestPayload else { return nil }
            return digestSize(p)

        case .insight:
            guard let p = payload as? InsightPayload else { return nil }
            return insightSize(p)

        case .todoList:
            guard let p = payload as? TodoListPayload else { return nil }
            return todoSize(itemCount: p.items.count)

        case .agentSummary:
            guard let p = payload as? AgentSummaryPayload else { return nil }
            return agentSize(completed: p.completed.count, stats: p.stats?.count ?? 0)
        }
    }

    private static func digestSize(_ p: DigestPayload) -> CardSize {
        let sections = p.sections?.count ?? 0
        if sections >= 2 { return .hero }      // rich multi-section article
        if sections == 1 { return .wide }
        // No sections — size on body length alone.
        if p.body.count >= digestBodyWide { return .wide }
        if p.body.count >= digestBodyMedium { return .medium }
        return .small
    }

    private static func insightSize(_ p: InsightPayload) -> CardSize {
        let hasCitations = !(p.citations?.isEmpty ?? true)
        if hasCitations {
            // Citations want width; hero only if the body also fills the height.
            return p.body.count >= insightBodyHero ? .hero : .wide
        }
        if p.body.count >= insightBodyWide { return .wide }
        if p.body.count >= insightBodyMedium { return .medium }
        return .small
    }

    private static func todoSize(itemCount: Int) -> CardSize {
        switch itemCount {
        case ...1: return .small
        case 2...3: return .medium
        case 4...6: return .wide
        default: return .hero
        }
    }

    private static func agentSize(completed: Int, stats: Int) -> CardSize {
        if completed <= 1 && stats == 0 { return .small }
        if completed <= 2 && stats <= 2 { return .medium }
        if completed <= 5 { return .wide }
        return .hero
    }

    // MARK: - Ordering

    /// Geometry rank (small < medium < wide < hero), so "downgrade-only" is a
    /// single comparison. Explicit map — does not rely on enum declaration order.
    private static func rank(_ size: CardSize) -> Int {
        switch size {
        case .small:  return 0
        case .medium: return 1
        case .wide:   return 2
        case .hero:   return 3
        }
    }
}
