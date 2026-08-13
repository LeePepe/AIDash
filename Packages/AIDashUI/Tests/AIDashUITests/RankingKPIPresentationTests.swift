import Testing
import SwiftUI
import Foundation
import AIDashCore
import DesignKit
@testable import AIDashUI

// MARK: - Ranking / KPI / scatter presentation repair (MY-1400)
//
// The MY-1396 rendered design gate failed light AND dark. This suite pins the
// verified findings from that gate so a regression fails here rather than in a
// screenshot review three issues later. One section per finding.
//
// Both schemes are exercised wherever the finding was scheme-dependent — a
// `Theme` is constructed per scheme rather than relying on an ambient
// `colorScheme`, because these are token/geometry assertions, not rendered
// pixels.
//
// NOT covered here, deliberately: the reviewer's "the relationship container
// has no card container" finding. That is `.bare` chrome for a single-card
// container, mandated by constitution §Container Chrome Rule A (MY-1306), and
// it was verified as a false positive. `bareChromeSurvivesForSingleCardContainer`
// below pins it as correct so a later run cannot "fix" it.

@MainActor
@Suite("Ranking / KPI / scatter presentation (MY-1400)")
struct RankingKPIPresentationTests {

    private static let schemes: [(name: String, isDark: Bool)] = [
        ("light", false), ("dark", true),
    ]

    private static func theme(isDark: Bool) -> Theme {
        Theme(seed: .lime, neutral: .slate, isDark: isDark)
    }

    // MARK: - Finding 1: star / value collision on the ranking card
    //
    // `CardRouter` floats the whole-card star at top-trailing +8pt. A barList
    // with no header band had its FIRST ROW's trailing value read-out in that
    // band, so the star landed on "41%". The repair consumes the Core header
    // contract (MY-1398) and reserves an affordance gutter in the top band.

    @Test("the affordance gutter is derived from the tokens the star overlay actually uses")
    func affordanceGutterIsDerivedNotMeasured() {
        // Derived = star hit target + the router's own trailing inset. A
        // screenshot-measured constant would drift the moment either changes;
        // this asserts the derivation, not a number.
        #expect(AIDashSpacing.cardAffordanceGutter
                == AIDashSpacing.starButtonHitTarget + AIDashSpace.s8)
        // And it must actually be wide enough to clear the control.
        #expect(AIDashSpacing.cardAffordanceGutter > AIDashSpacing.starButtonHitTarget)
    }

    @Test("CardRouter still insets the star by the value the gutter is derived from")
    func routerInsetMatchesGutterDerivation() throws {
        // The gutter's correctness depends on the router's padding. If the
        // router changes its inset without the token following, the reservation
        // silently stops clearing the star — so pin the coupling in source.
        let source = try DesignTokensComplianceTests.cardViewSource(named: "CardRouter")
        #expect(source.contains(".padding(.trailing, AIDashSpace.s8)"),
                "the star overlay's trailing inset is the second term of AIDashSpacing.cardAffordanceGutter")
    }

    @Test("a titled bar-list renders a header band that reserves the affordance gutter")
    func titledBarListReservesGutterInHeader() throws {
        let source = try DesignTokensComplianceTests.rendererSource(for: .barList)
        #expect(source.contains("payload.headerTitle"),
                "barList must consume the Core header contract (BarListPayload.headerTitle), not re-derive it")
        #expect(source.contains(".padding(.trailing, AIDashSpacing.cardAffordanceGutter)"),
                "the header band must reserve the star's gutter")
        // Materialise both shapes so a layout regression crashes here.
        _ = Self.barList(titled: true).body
        _ = Self.barList(titled: false).body
    }

    @Test("an untitled bar-list reserves the gutter on the first row instead — the star's band is never unreserved")
    func untitledBarListReservesGutterOnFirstRow() throws {
        let source = try DesignTokensComplianceTests.rendererSource(for: .barList)
        #expect(source.contains("trailingInset"),
                "the row must accept a trailing inset so the TOP row can clear the star")
        #expect(source.contains("payload.headerTitle == nil && index == 0"),
                "exactly the first row of an untitled ranking reserves the gutter — the case that collided")
    }

    @Test("the gutter is reserved on the label line only — the bar keeps its full comparative width")
    func gutterDoesNotDistortTheBar() throws {
        let source = try DesignTokensComplianceTests.rendererSource(for: .barList)
        // The bar is the comparative channel. Insetting it would shorten every
        // top row by ~36pt and make the ranking lie about its own scale, which
        // would be a worse defect than the collision being fixed.
        let barBody = try #require(source.range(of: "private var bar: some View"))
        let barSource = String(source[barBody.lowerBound...].prefix(400))
        #expect(!barSource.contains("trailingInset"),
                "the bar must not consume the affordance gutter — only the label/value line does")
    }

    // MARK: - Finding 2: KPI subtitles and status-pill text off inaccessible roles
    //
    // The gate measured 1.69:1 (light) / 2.12:1 (dark) on KPI subtitles and
    // 1.95:1 on light status pills. DesignKit (MY-1399) landed the accessible
    // roles; this pins that AIDashUI consumes them and stops using SwiftUI's
    // `.secondary` / `.tertiary`, which resolve against the platform ground
    // rather than the theme's card ground.

    @Test("the metric renderer resolves label + context through DesignKit text roles, not SwiftUI hierarchy")
    func kpiLabelsUseAccessibleTextRoles() throws {
        let source = try DesignTokensComplianceTests.rendererSource(for: .metric)
        #expect(source.contains("theme.neutrals.text(.body)"),
                "KPI label + context are body copy and must resolve through TextRole.body")
        #expect(!source.contains(".foregroundStyle(.tertiary)"),
                "KPI copy must not use SwiftUI's .tertiary — it is not theme-aware and measured 1.69:1")
        #expect(!source.contains("Color(hex:") && !source.contains("Color(red:"),
                "no hard-coded colors in the metric renderer")
    }

    @Test("TextRole.body never resolves to text3 in either scheme — the rule the gate broke")
    func bodyRoleNeverResolvesToText3() {
        for scheme in Self.schemes {
            let neutrals = Self.theme(isDark: scheme.isDark).neutrals
            #expect(neutrals.text(.body) == neutrals.text2,
                    "\(scheme.name): body copy must be text2")
            #expect(neutrals.text(.body) != neutrals.text3,
                    "\(scheme.name): north-star §4 — body copy must never be text3")
        }
    }

    @Test("the bar-list overflow line uses the meta role rather than SwiftUI .tertiary")
    func barListOverflowUsesMetaRole() throws {
        let source = try DesignTokensComplianceTests.rendererSource(for: .barList)
        #expect(source.contains("theme.neutrals.text(.meta)"),
                "the '+N more' line is metadata and must resolve through TextRole.meta")
        #expect(!source.contains(".foregroundStyle(.tertiary)"),
                "the bar-list renderer must not use SwiftUI's .tertiary")
    }

    @Test("status-pill text resolves through the on-subtle role, and in light mode is genuinely darkened")
    func statusPillTextUsesOnSubtleRole() {
        // The pill's failure was text and fill in the SAME color, measured at
        // 1.95:1 in LIGHT mode. DesignKit owns the repair (MY-1399) and the
        // WCAG ratios; AIDashUI only consumes StatusPill, so this pins the
        // property the KPI trend pill depends on rather than re-testing those
        // ratios one layer down.
        let light = Self.theme(isDark: false)
        #expect(light.successOnSubtle != light.success,
                "light success pill text must be darkened off its own fill — that pair measured 1.95:1")
        #expect(light.warningOnSubtle != light.warning,
                "light warning pill text must be darkened off its own fill")
        #expect(light.dangerOnSubtle != light.danger,
                "light danger pill text must be darkened off its own fill")
        // Dark success/warning are documented as already legible and returned
        // unchanged; only danger is brightened. Asserting a difference there
        // would be asserting a change DesignKit deliberately did not make.
        let dark = Self.theme(isDark: true)
        #expect(dark.dangerOnSubtle != dark.danger,
                "dark danger pill text must be brightened off its own fill")
        // What must hold in BOTH schemes: the role exists and is reachable, so
        // a consumer never has to pick a status text color by eye.
        for scheme in Self.schemes {
            let theme = Self.theme(isDark: scheme.isDark)
            #expect(theme.successOnSubtle == Semantic.successOnSubtle(isDark: scheme.isDark),
                    "\(scheme.name): the pill text role must come from DesignKit's Semantic tokens")
            #expect(theme.text(.body) == theme.neutrals.text2,
                    "\(scheme.name): the neutral pill's text role is body, never text3")
        }
    }

    // MARK: - Finding 3: the fourth KPI card's broken baseline
    //
    // The ratio card had no delta pill and a short gauge band against its
    // siblings' bar-sparks, so it broke the four-card baseline and left a
    // ~69pt cavity in dark.

    @Test("a ratio band and a series band reserve the SAME height — the four-card baseline")
    func gaugeAndSparkBandsAreEqualHeight() {
        let card = Self.kpiCard(items: [.init(label: "Coverage", value: 87, ratio: 0.87)])
        let ratio = MetricPayload.Item(label: "缓存命中率", value: 63, unit: "%", ratio: 0.63)
        let series = MetricPayload.Item(
            label: "Token", value: 217_836_228, trend: .down,
            series: [498, 720, 767, 511, 325, 289, 217], higherIsBetter: false
        )
        let gauge = card.resolvedVizKind(for: ratio)
        let spark = card.resolvedVizKind(for: series)
        #expect(gauge == .gauge)
        #expect(spark == .sparkbars)
        // The gauge used to reserve 44pt against the spark's 52pt, so the ratio
        // card's band ended short and the difference pooled into a cavity at
        // the card bottom.
        #expect(gauge.height == spark.height,
                "a ratio card and a series card must reserve the same instrument band (north-star §6)")
        #expect(gauge.height > 0, "an instrument that is drawn must reserve a band")
        // A cell with nothing to plot still reserves nothing.
        let flat = MetricPayload.Item(label: "开 PR", value: 1, trend: .flat, series: [2, 2, 2])
        #expect(card.resolvedVizKind(for: flat) == .none)
        #expect(card.resolvedVizKind(for: flat).height == 0)
    }

    @Test("both instruments sit on the band's bottom edge so the KPI row reads as one baseline")
    func instrumentsShareABaseline() throws {
        let source = try DesignTokensComplianceTests.rendererSource(for: .metric)
        #expect(source.contains("maxHeight: .infinity, alignment: .bottom"),
                "the gauge must be bottom-aligned to meet Sparkbars, which draws up from the bottom edge")
    }

    @Test("a pill-less cell that draws an instrument reserves the pill row even as a lone-item card")
    func loneRatioCardReservesThePillRow() {
        let card = Self.kpiCard(items: [.init(label: "缓存命中率", value: 63, unit: "%", ratio: 0.63)])
        let ratio = MetricPayload.Item(label: "缓存命中率", value: 63, unit: "%", ratio: 0.63)
        // This is the actual fourth-KPI defect: four `small` metric cards are
        // four separate single-item payloads, so a payload-scoped "does any
        // item have a pill" check could never see the pilled siblings. The
        // lone ratio item HAS no pill and must still reserve the row.
        #expect(card.pillLabel(for: ratio) == nil)
        #expect(card.resolvedVizKind(for: ratio).reservesPillRow,
                "a lone ratio card must reserve the pill row or its band rides ~20pt above its pilled siblings")
        _ = card.body
    }

    @Test("a chart-less cell still reserves nothing — the sparse-data reclaim is intact")
    func chartlessCellStaysCompact() {
        let card = Self.kpiCard(items: [.init(label: "开 PR", value: 1, trend: .flat)])
        let noViz = MetricPayload.Item(label: "开 PR", value: 1, trend: .flat)
        #expect(card.resolvedVizKind(for: noViz) == .none)
        #expect(!card.resolvedVizKind(for: noViz).reservesPillRow,
                "a cell with no instrument must stay compact rather than reserve an always-on empty row")
        #expect(MetricCardView.isFlat([100, 100, 100, 100]))
        _ = card.body
    }

    @Test("a delta pill is still drawn whenever the item carries one — the treatment is never suppressed")
    func deltaTreatmentSurvivesForRatioAndSeriesAlike() {
        let card = Self.kpiCard(items: [.init(label: "Coverage", value: 87, ratio: 0.87)])
        // A ratio item that DOES carry a trend gets its delta pill; the choice
        // of instrument must not decide whether a user-visible delta renders.
        let ratioWithTrend = MetricPayload.Item(
            label: "缓存命中率", value: 63, unit: "%", trend: .up,
            series: [55, 58, 63], ratio: 0.63, higherIsBetter: true
        )
        #expect(card.pillLabel(for: ratioWithTrend) != nil,
                "a ratio item with a trend must still draw its delta pill")
        // And a genuinely signal-less item still draws nothing — the sparse-data
        // whitespace reclaim must not regress into an always-on empty row.
        let noSignal = MetricPayload.Item(label: "自动化占比", value: 100, unit: "%", ratio: 1.0)
        #expect(card.pillLabel(for: noSignal) == nil)
    }

    // MARK: - Finding 4: unequal ranking cards + a bar that never reaches full width
    //
    // The two ranking cards ended at different bottom edges, and the top-ranked
    // 41% row drew a short bar.

    @Test("a populated framed card stretches to its row height so side-by-side cards end level")
    func framedCardsStretchToRowHeight() throws {
        let source = try DesignTokensComplianceTests.designTokensSource()
        #expect(source.contains("maxHeight: stretches ? .infinity : nil"),
                "a populated framed card must fill the height its row proposes")
        #expect(source.contains("let stretches = minHeightOverride == nil"),
                "the empty state must NOT stretch — it exists to collapse")
    }

    @Test("the grid proposes one height per row, which is what the card now fills")
    func gridProposesRowHeight() throws {
        // The stretch only equalizes if the layout actually hands both cards the
        // same proposal. Pin the coupling rather than assume it.
        let source = try DesignTokensComplianceTests.surfaceSource("Layout/AutoLayout")
        #expect(source.contains("proposal: ProposedViewSize(width: cellWidth, height: rowHeight)"),
                "TokenGridLayout must propose the row's height to every card in that row")
    }

    @Test("the top-ranked row draws a full-width bar — 41% of a 41% max is the whole track")
    func barListNormalizesAgainstItsOwnMaximum() {
        // The gate's exact fixture: 41 / 27 / 19 / 13, where 41% is the top rank
        // and must render as the full comparative bar.
        let items: [BarListPayload.Item] = [
            .init(label: "取消后重做", value: 41, valueText: "41%", semantic: "warning"),
            .init(label: "review 往返", value: 27, valueText: "27%"),
            .init(label: "跨层返工", value: 19, valueText: "19%"),
            .init(label: "门禁失败", value: 13, valueText: "13%"),
        ]
        let fractions = BarListCardView.fractions(for: items)
        #expect(fractions[0] == 1.0, "the largest visible row must fill the track")
        #expect(fractions[1] == 27.0 / 41.0)
        #expect(fractions[2] == 19.0 / 41.0)
        #expect(fractions[3] == 13.0 / 41.0)
        // Descending input stays descending on screen.
        #expect(fractions == fractions.sorted(by: >))
    }

    @Test("normalization uses the DRAWN rows, so truncation cannot leave every bar short")
    func barListNormalizesOverVisibleRows() {
        // A payload whose largest item is folded into "+N more" would otherwise
        // scale every visible bar against a magnitude that is not on screen.
        let visible: [BarListPayload.Item] = [
            .init(label: "b", value: 30),
            .init(label: "c", value: 15),
        ]
        let fractions = BarListCardView.fractions(for: visible)
        #expect(fractions[0] == 1.0,
                "the top row of what is actually drawn must reach full width")
        #expect(fractions[1] == 0.5)
    }

    @Test("degenerate magnitudes yield zero-width bars rather than NaN or an inverted scale")
    func barListFractionsAreTotal() {
        #expect(BarListCardView.fractions(for: []) == [])
        // All zeros: no scale exists, so nothing is drawn — never a divide by 0.
        #expect(BarListCardView.fractions(for: [
            .init(label: "a", value: 0), .init(label: "b", value: 0),
        ]) == [0, 0])
        // Negatives clamp to 0 and do not become a negative width.
        let mixed = BarListCardView.fractions(for: [
            .init(label: "a", value: 10), .init(label: "b", value: -5),
        ])
        #expect(mixed[0] == 1.0)
        #expect(mixed[1] == 0)
        for f in mixed { #expect(f.isFinite && (0...1).contains(f)) }
    }

    // MARK: - Finding 5: scatter gridlines + missing legend

    @Test("every relationship axis drops its grid line per north-star §7")
    func scatterHasNoGridlines() throws {
        let source = try DesignTokensComplianceTests.cardViewSource(named: "RelationshipChart")
        #expect(source.contains("RelationshipChartAxis.gridless()"),
                "the scatter must render its axes through the gridless helper")
        #expect(!source.contains("AxisGridLine("),
                "no relationship chart may emit an AxisGridLine — §7 says 无网格")
        // Ticks and value labels stay: a scatter with unreadable axes is data
        // loss, not restraint.
        #expect(source.contains("AxisTick()") && source.contains("AxisValueLabel()"),
                "dropping the grid must not drop the axis value labels")
    }

    @Test("a multi-category scatter shows the legend that keys its color channel")
    func scatterShowsLegendWhenColorCarriesMeaning() {
        let points: [RelationshipPayload.Point] = [
            .init(label: "AIDash", x: 2.1, y: 88, magnitude: 34, category: "project"),
            .init(label: "Multica", x: 5.6, y: 69, magnitude: 28, category: "workspace"),
        ]
        let legend = RelationshipCategoryPalette.legend(for: points)
        #expect(legend.isKeyed, "two categories means color discriminates — the legend must render")
        #expect(legend.domain == ["project", "workspace"],
                "legend rows follow first-appearance order, matching the palette's slot assignment")
    }

    @Test("a single-category scatter keeps the legend hidden — one row explains nothing")
    func scatterHidesLegendWhenColorIsUninformative() {
        let single: [RelationshipPayload.Point] = [
            .init(label: "AIDash", x: 2.1, y: 88, category: "project"),
            .init(label: "aidata", x: 6.9, y: 62, category: "project"),
        ]
        #expect(!RelationshipCategoryPalette.legend(for: single).isKeyed)
        // No categories at all: still hidden, and still a bindable domain.
        let uncategorized: [RelationshipPayload.Point] = [
            .init(label: "AIDash", x: 2.1, y: 88),
        ]
        let legend = RelationshipCategoryPalette.legend(for: uncategorized)
        #expect(!legend.isKeyed)
        #expect(!legend.domain.isEmpty,
                "the style scale needs a non-empty domain to bind against even when hidden")
    }

    @Test("legend key and symbol color are resolved from one value, so they cannot disagree")
    func legendKeyAndColorAgree() {
        let points: [RelationshipPayload.Point] = [
            .init(label: "AIDash", x: 2.1, y: 88, category: "project"),
            .init(label: "Skills", x: 4.8, y: 74, category: "workspace"),
            .init(label: "aidata", x: 6.9, y: 62, category: "project"),
        ]
        let legend = RelationshipCategoryPalette.legend(for: points)
        for scheme in Self.schemes {
            let theme = Self.theme(isDark: scheme.isDark)
            let range = legend.colors(theme: theme)
            #expect(range.count == legend.domain.count,
                    "\(scheme.name): the scale's range must have one color per legend row")
            for point in points {
                let slot = legend.slot(for: point)
                #expect(legend.color(for: point, theme: theme) == range[slot],
                        "\(scheme.name): a point's symbol color must equal its own legend swatch")
            }
            // Same category → same swatch; different category → different swatch.
            #expect(legend.color(for: points[0], theme: theme)
                    == legend.color(for: points[2], theme: theme))
            #expect(legend.color(for: points[0], theme: theme)
                    != legend.color(for: points[1], theme: theme))
        }
    }

    @Test("an uncategorized point in a mixed payload gets its own legend row, never a real category")
    func mixedCategoryPointsAreNeverFoldedIntoARealCategory() throws {
        // Two REAL categories plus one uncategorized point — the payload shape
        // where folding absence into `domain.first` colored and described the
        // ungrouped mark as "project".
        let points: [RelationshipPayload.Point] = [
            .init(label: "AIDash", x: 2.1, y: 88, category: "project"),
            .init(label: "Skills", x: 4.8, y: 74, category: "workspace"),
            .init(label: "unknown", x: 3.0, y: 70),
            .init(label: "blank", x: 3.6, y: 66, category: ""),
        ]
        let legend = RelationshipCategoryPalette.legend(for: points)

        #expect(legend.domain.count == 3,
                "two real categories plus one uncategorized row")
        #expect(Array(legend.domain.prefix(2)) == ["project", "workspace"],
                "real categories keep first-appearance order and lead the legend")
        let uncategorizedKey = try #require(legend.uncategorizedKey)
        #expect(legend.domain.last == uncategorizedKey,
                "the uncategorized row sits last, after every real category")

        for point in [points[2], points[3]] {
            // The blocker, stated directly: a nil / empty category may never be
            // represented as any real category — not in the key, not in color.
            #expect(legend.entry(for: point) == .uncategorized)
            #expect(!legend.categories.contains(legend.key(for: point)),
                    "\(point.label): its legend key must not be a real category")
            for scheme in Self.schemes {
                let theme = Self.theme(isDark: scheme.isDark)
                let tint = legend.color(for: point, theme: theme)
                #expect(tint == RelationshipCategoryPalette.uncategorizedColor(theme),
                        "\(scheme.name)/\(point.label): absence is drawn in the neutral token")
                for index in legend.categories.indices {
                    #expect(tint != RelationshipCategoryPalette.color(slot: index, theme: theme),
                            "\(scheme.name)/\(point.label): must not wear any category's swatch")
                }
            }
        }
    }

    @Test("a legend row and its swatch agree for every point, uncategorized included")
    func mixedCategoryLegendSwatchesMatchThePlottedColors() {
        let points: [RelationshipPayload.Point] = [
            .init(label: "AIDash", x: 2.1, y: 88, category: "project"),
            .init(label: "Skills", x: 4.8, y: 74, category: "workspace"),
            .init(label: "unknown", x: 3.0, y: 70),
        ]
        let legend = RelationshipCategoryPalette.legend(for: points)
        #expect(legend.isKeyed, "three rows means color discriminates — the legend must render")
        for scheme in Self.schemes {
            let theme = Self.theme(isDark: scheme.isDark)
            let range = legend.colors(theme: theme)
            #expect(range.count == legend.domain.count,
                    "\(scheme.name): the scale's range must have one color per legend row")
            for point in points {
                #expect(legend.color(for: point, theme: theme) == range[legend.slot(for: point)],
                        "\(scheme.name): a point's symbol color must equal its own legend swatch")
            }
        }
    }

    @Test("one real category plus uncategorized points still shows the legend — two colors are on screen")
    func singleCategoryPlusUncategorizedStaysKeyed() {
        let points: [RelationshipPayload.Point] = [
            .init(label: "AIDash", x: 2.1, y: 88, category: "project"),
            .init(label: "unknown", x: 3.0, y: 70),
        ]
        let legend = RelationshipCategoryPalette.legend(for: points)
        #expect(legend.isKeyed,
                "one category and one uncategorized row are two distinct colors; hiding the legend would leave the second unexplained")
        #expect(legend.entry(for: points[1]) == .uncategorized)
        #expect(legend.key(for: points[1]) != "project")
    }

    @Test("a real category literally named Uncategorized does not collapse into the absence row")
    func uncategorizedRowSurvivesANameCollision() {
        let points: [RelationshipPayload.Point] = [
            .init(label: "AIDash", x: 2.1, y: 88,
                  category: RelationshipCategoryPalette.Legend.uncategorizedLabel),
            .init(label: "Skills", x: 4.8, y: 74, category: "workspace"),
            .init(label: "unknown", x: 3.0, y: 70),
        ]
        let legend = RelationshipCategoryPalette.legend(for: points)
        #expect(Set(legend.domain).count == legend.domain.count,
                "two identical domain values would merge into one Swift Charts row")
        #expect(legend.key(for: points[0])
                == RelationshipCategoryPalette.Legend.uncategorizedLabel,
                "the REAL category keeps the name the payload gave it")
        #expect(legend.key(for: points[2]) != legend.key(for: points[0]),
                "the absence row must stay distinct from the same-named real category")
        #expect(legend.entry(for: points[2]) == .uncategorized)
    }

    @Test("with no categories at all there is no uncategorized row — nothing to distinguish")
    func fullyUncategorizedPayloadHasNoAbsenceRow() {
        let points: [RelationshipPayload.Point] = [
            .init(label: "AIDash", x: 2.1, y: 88),
            .init(label: "aidata", x: 6.9, y: 62, category: ""),
        ]
        let legend = RelationshipCategoryPalette.legend(for: points)
        #expect(legend.categories.isEmpty)
        #expect(legend.uncategorizedKey == nil,
                "flagging every point as missing would be noise, not information")
        #expect(!legend.isKeyed)
        #expect(legend.domain == [RelationshipCategoryPalette.Legend.unkeyed],
                "the style scale still needs a non-empty domain to bind against")
        for point in points { #expect(legend.entry(for: point) == .unkeyed) }
    }

    @Test("the scatter materialises at every size with the legend wired to the scale")
    func scatterRendersWithKeyedLegend() throws {
        let source = try DesignTokensComplianceTests.cardViewSource(named: "RelationshipChart")
        #expect(source.contains(".chartForegroundStyleScale("),
                "the legend requires an explicit scale so its swatches match the plotted colors")
        #expect(source.contains("legend.isKeyed ? .visible : .hidden"),
                "legend visibility must follow whether color actually discriminates")
        // Scheme-dependent behavior is asserted on the resolved tokens above;
        // here the plot just has to materialise at every geometry.
        for size in CardSize.allCases {
            _ = RelationshipCardView(
                payload: Self.scatterPayload, size: size, style: .neutral
            ).body
        }
    }

    // MARK: - Verified false positive: single-card relationship chrome
    //
    // Both design reviewers filed "the 关联 · 成本 × 产出 section has no card
    // container" as a P0. It is `.bare` chrome for a single-card container,
    // mandated by constitution §Container Chrome Rule A. Pinned here so a later
    // repair run cannot "fix" it back into a frame-inside-a-frame.

    @Test("a single-card relationship container keeps constitution-mandated .bare chrome")
    func bareChromeSurvivesForSingleCardContainer() {
        let container = ContainerModel(
            id: "c-relationship", title: "关联 · 成本 × 产出", subtitle: nil,
            order: 30, layout: .grid, style: .neutral
        )
        container.cards = [CardModel(
            id: "card-relationship", type: .relationship, size: .wide,
            style: .neutral, payloadJSON: Self.scatterPayloadJSON
        )]
        let view = ContainerView(container: container)
        #expect(view.effectiveCardCount == 1)
        #expect(view.chromeMode == .bare,
                "Rule A: a lone card drops its frame — the container title already carries the grouping. This reviewer finding was a verified false positive and must NOT be 'repaired'.")
    }

    // MARK: - Fixtures

    private static func barList(titled: Bool) -> BarListCardView {
        BarListCardView(
            payload: BarListPayload(
                items: [
                    .init(label: "取消后重做", value: 41, valueText: "41%", semantic: "warning"),
                    .init(label: "review 往返", value: 27, valueText: "27%"),
                    .init(label: "跨层返工", value: 19, valueText: "19%"),
                    .init(label: "门禁失败", value: 13, valueText: "13%"),
                ],
                title: titled ? "返工来源" : nil
            ),
            size: .medium,
            style: .neutral
        )
    }

    private static func kpiCard(items: [MetricPayload.Item]) -> MetricCardView {
        MetricCardView(payload: MetricPayload(items: items), size: .small, style: .neutral)
    }

    private static let scatterPayload = RelationshipPayload(
        title: "Cost × outcome",
        visualization: .scatter,
        xAxis: .init(label: "Cost per completed task", unit: "USD"),
        yAxis: .init(label: "First-pass completion proxy", unit: "%"),
        points: [
            .init(label: "AIDash", x: 2.1, y: 88, magnitude: 34, category: "project"),
            .init(label: "Financial", x: 3.4, y: 81, magnitude: 21, category: "project"),
            .init(label: "Skills", x: 4.8, y: 74, magnitude: 12, category: "workspace"),
            .init(label: "Multica", x: 5.6, y: 69, magnitude: 28, category: "workspace"),
        ],
        sampleSize: 34,
        timeWindow: "7d",
        metricDefinition: "completed is a pipeline proxy, not objective correctness",
        summary: "AIDash has the lowest observed cost at the highest completion proxy."
    )

    private static var scatterPayloadJSON: Data {
        // swiftlint:disable:next line_length
        Data(#"{"title":"Cost × outcome","visualization":"scatter","xAxis":{"label":"Cost per completed task","unit":"USD"},"yAxis":{"label":"First-pass completion proxy","unit":"%"},"points":[{"label":"AIDash","x":2.1,"y":88,"magnitude":34,"category":"project"},{"label":"Multica","x":5.6,"y":69,"magnitude":28,"category":"workspace"}],"sampleSize":34,"timeWindow":"7d","metricDefinition":"completed is a pipeline proxy, not objective correctness","summary":"AIDash has the lowest observed cost at the highest completion proxy."}"#.utf8)
    }
}
