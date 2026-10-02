# Baseline design system (light + Liquid Glass)

The single reference for every screen builder. Everything a screen renders comes from the tokens and
components in `Baseline/Components/`; screens never spell a colour, a font size or a corner radius, and
never compute a baseline, band or average (those come from `BaselineReadouts` / `BaselineReadiness` /
the snapshot models). Vocabulary: **HRV / Resting HR / Readiness / Sleep / Effort / Journal**; WHOOP
only nominatively. Trademark guardrail: at most two `MetricRing`s on one screen (Home: HRV and Resting
HR, each in its own tile); the Sleep ring lives on the Sleep tab; Readiness is a pill and a sentence,
never a ring. Platform: iOS 26.0 (`project.yml` deployment target for Baseline, BaselineTests,
BaselineUITests). No availability checks anywhere.

## Information architecture (owner decision; overrides the spec's screen list where they conflict)

THREE tabs: **Home** (`house`), **Trends** (`chart.xyaxis.line`), **Sleep** (`moon.zzz`). Settings is
a gear in the top-right of the navigation bar on all three (`BaselineToolbarLink` → `SettingsScreen()`).
Journal is NOT a tab.

| Tab | Root | Structure |
|---|---|---|
| Home | `Screens/Today/TodayScreen.swift` (struct name may stay `TodayScreen`; tab label "Home") | Day-by-day like WHOOP: nav title = the selected day (`BaselineDaySwitcher.title(for:)`), `BaselineDaySwitcher(style: .glass)` pinned under the bar, `.baselineDaySwipe` on the content; every card shows THAT day (readiness card with the Progress chevron, HRV + Resting HR rings, that night's sleep, that day's effort + workouts, Signals on today only); a floating `GlassCTA(title: "Journal", systemImage: "checklist", fullWidth: false)` opens `JournalSheet(day:)` for the selected day; `StrapStatusPill` stays in the toolbar beside the gear |
| Trends | `Screens/Trends/TrendsScreen.swift` | `BaselineSegmentedPicker(style: .glass)` pinned under the bar over THREE sections: "Trends" (the metric charts; the 7D/30D/90D `BaselineRangePicker(style: .flat)` at the top of the section content), "Progress" (`ProgressScreen`'s body embedded as a section, its horizon picker `.flat`), "Habits" (`JournalPatternsView()`). The Effort card keeps the "All workouts" `BaselineChevronRow` → `WorkoutsScreen()` |
| Sleep | `Screens/Sleep/SleepScreen.swift` | unchanged structure, restyled |

Journal (`Screens/Journal/`) exposes exactly two entry points: `JournalSheet(day: String)` (a sheet:
day label, that day's habit chips, "Add habit", Done) and `JournalPatternsView()` (the effects card(s)
+ dose rows + empty states, built to sit inside Trends' `LazyVStack`). The old `JournalScreen` root is
gone. Settings and everything under it (Devices, Apple Health, Import, Compare, Export,
Profile, Notifications, About) is unchanged in structure.

Name contracts between builders: `JournalSheet(day:)`, `JournalPatternsView()`, `SettingsScreen()`,
`ProgressScreen()` (may be reused as the embedded Progress section body), `WorkoutsScreen()`.
`BaselineRoot` (three tabs, `--tab home|trends|sleep` with `today` / `journal` / `settings` aliases,
`pendingTab "journal"` → home + sheet) belongs to the Home builder.

Glass budget per tab under this IA: Home = pinned day switcher (1) + floating Journal button (1) +
system bars; Trends = pinned section control (1) + bars; Sleep = bars only; Settings = ≤ 7 pinned
headers. Only ONE pinned row per screen: Trends' range picker is therefore `.flat` in the content, not
a second bar.

## Principle

Flat light paper (`background`) with opaque white cards carrying the data. Glass ONLY on the layer that
floats above content and refracts what scrolls beneath it: the tab bar, the navigation bar and its
toolbar items (automatic), the one pinned control under the bar (`BaselineScreen.pinned`: Home's day
switcher, Trends' section control), the strap status pill and the gear (toolbar items, so no extra
glass), floating actions over the background (`GlassCTA`: Welcome's column, Home's Journal button) and
pinned Settings section headers (`BaselineSectionLabel(style: .glass)`). Cards, chips, charts, rows,
pills inside cards, in-card CTAs and in-card pickers are flat. Never glass on glass. Text on glass is
always ink. Budget: ≤ 4 custom glass regions on any screen plus the system bars.

## Verified iOS 26.5 SDK signatures (iPhoneSimulator26.5.sdk swiftinterfaces, re-grepped this round)

```swift
// SwiftUICore
func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View
struct Glass: Equatable, Sendable { static var regular: Glass; static var clear: Glass; static var identity: Glass
               func tint(_ color: Color?) -> Glass; func interactive(_ isEnabled: Bool = true) -> Glass }
struct GlassEffectContainer<Content: View>: View { init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) }
// SwiftUI
extension PrimitiveButtonStyle where Self == GlassButtonStyle { static var glass: GlassButtonStyle }           // 26.0
extension PrimitiveButtonStyle where Self == GlassProminentButtonStyle { static var glassProminent }           // 26.0
struct GlassButtonStyle { init(); @available(iOS 26.1) init(_ glass: Glass) }   // init(_:) is 26.1 → NOT used
func tabBarMinimizeBehavior(_ behavior: TabBarMinimizeBehavior) -> some View    // .automatic / .onScrollDown / .onScrollUp / .never
func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View   // .automatic / .hard / .soft
func safeAreaBar(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                 @ViewBuilder content: () -> some View) -> some View
func navigationSubtitle<S: StringProtocol>(_ subtitle: S) -> some View          // iOS 26.0
```

Not used anywhere, by decision: `glassEffectID`, `glassEffectUnion`, `glassEffectTransition`,
`Glass.clear`, tinted custom glass (`Glass.tint`), `GlassButtonStyle.init(_:)`. Only `.glassProminent`
carries a tint (`accent`).

## Tokens — `BaselineTheme`

Colour literals live only in `BaselineTheme.swift`, through `fileprivate Color.init(baselineHex:opacity:)`.
Contrast is WCAG 2.1 on white (cards) / on `#F4F5F8` (the page).

| Token | Value | Use |
|---|---|---|
| `background` | `#F4F5F8` | the page; also `LaunchBackground.colorset` |
| `backgroundTop` / `backgroundBottom` | `#F7F8FB` / `#F2F3F7` | `BaselineBackground`'s near-flat wash |
| `card` | `#FFFFFF` | card surface (opaque) |
| `cardShadow` | `#111827` @ 0.06 | ONE shadow per card: radius 16, x 0, y 6. Never on rows or chips |
| `hairline` | `#111827` @ 0.08 | dividers; chart grid = `hairline.opacity(0.75)` |
| `ringTrack` | `#E9EBF1` | the unfilled ring |
| `chipFill` | `#F4F5F8` | the "no" chip fill inside a white card |
| `fill` / `fillStroke` | `#111827` @ 0.04 / 0.08 | flat segmented-picker / day-switcher track |
| `text` | `#111827` | ink, 17.7 / 16.3 |
| `textSecondary` | `#4B5563` | 7.6 / 6.9 |
| `textTertiary` | `#5F6B7B` | ALL caption text, axis labels, section labels, chevrons, footnotes (5.4 / 5.0) |
| `inactive` | `#9CA3AF` | NON-TEXT only (2.5:1): disabled glyphs, unanswered-chip stroke, not-connected dot |
| `marker` | white | the scrubbed chart point's fill (`BaselineChartStyle.selectedPoint`) |
| `onAccent` | `#FFFFFF` | label on a filled accent control (5.2:1) |
| `accent` = `hrv` | `#0D7A72` | teal, 5.2 / 4.8. The one accent; tints prominent CTAs and selected controls |
| `rhr` | `#C8412A` | coral, 5.0 / 4.5 |
| `sleep` | `#4A4FD0` | indigo, 6.3 / 5.8 |
| `effort` | `#B45309` | amber, 5.0 / 4.6 |
| `good` / `watch` / `low` | `#15803D` / `#C2410C` / `#B91C1C` | judgements |
| `stageDeep` / `stageRem` / `stageLight` / `stageWake` | `#312E81` / `#6D5BD0` / `#8FB3F2` / `#F0B37E` | fills, swatches, 6pt dots only, never text; `stageColor(_:)` unchanged |
| `zone1…zone5`, `zoneColor(_:)` | `effort` @ 0.30 / 0.45 / 0.60 / 0.80 / 1.0 | HR zones |

Coloured text appears only INSIDE white cards, never directly on the page (rhr / effort / good are
4.5–4.6 on the background). Readiness tier colours: `ReadinessTier.baselineColor` (primed → good,
normal → accent, suppressed → watch; `BaselineReadiness.swift`, untouched).

Derived opacities (never ad hoc): band area = metric @ 0.12 (`BaselineChartStyle.bandOpacity`); dashed
baseline rule = metric @ 0.50 (`baselineOpacity`); ring band arc = metric @ 0.18; bars = metric @ 0.90
(`barOpacity`); flat pill fill = colour @ 0.10; selected segment / selected day chip = `accent` @ 0.14;
yes-chip fill = `accent` @ 0.12; icon tile fill = `accent` @ 0.10.

**Flat pill rule**: fill = colour @ 0.10, leading 6pt dot in the colour, TEXT IN INK. `BaselinePill` does
this for you; stage `StatCell` values are ink with `dot: stageColor`.

### Type (SF Rounded everywhere; nothing ad hoc)

| Token | Definition | Use |
|---|---|---|
| `hero(_ size = 44)` | semibold rounded, scales with Dynamic Type (large-title curve, capped at 1.5×) | 44 inside Home's rings (the ring grows to 168 at accessibility sizes); 36 for a duration numeral ("7h 24m": Last-night row, Sleep ring, Workout header); Welcome keeps `hero(54)` / `hero(34)` |
| `title` | `.title2` rounded semibold (22) | Workout detail's sport title |
| `stat` | 20 semibold rounded, scales with Dynamic Type (title3 curve, capped at 2×) | every `StatCell` value, Journal day number, effect delta, timing-grid values |
| `headline` | `.headline` rounded (17) | sentences that lead a card, CTA labels |
| `body` | `.body` rounded (17) | the one sentence in a card |
| `label` | `.subheadline` rounded medium (15) | card titles, chips, row titles |
| `caption` | `.footnote` rounded (13) | every secondary line, axis labels, section labels |
| `symbolSmall` / `symbol` / `symbolAccessory` | `.caption2` semibold / `.footnote` medium / `.subheadline` light | glyphs beside text (scale with Dynamic Type) |

Ring numerals carry `.monospacedDigit()`, `.minimumScaleFactor(0.75)`, `.contentTransition(.numericText())`
(done inside `MetricRing`).

### Layout

`gutter` 20 · `cardRadius` 28 (continuous; `cardShape`) · `cardPadding` 20 (ring tiles pass `padding: 16`)
· `cardSpacing` 14 (the `BaselineScreen` stack spacing) · `ringLineWidth` 10 (Sleep hero 12) ·
`ringSize` 128 (Home; Sleep passes 168) · chip = Capsule, padding h 14 / v 9 · pill h 10 / v 5 · status
pill h 10 / v 6 · pinned bar inner padding h 20 / v 6 · icon tile 30pt, radius 10 continuous.

## Components

### `BaselineScreen` — `BaselineTheme.swift`

```swift
BaselineScreen(title: BaselineDaySwitcher.title(for: day), titleMode: .inline, subtitle: syncStamp,
               pinned: { BaselineDaySwitcher(selection: $day, earliest: firstNight, style: .glass) }) { … }   // Home
BaselineScreen(title: "Trends", titleMode: .inline,
               pinned: { BaselineSegmentedPicker(options: TrendsSection.allCases, selection: $section,
                                                 label: { $0.label }, style: .glass) }) { … }                 // Trends
BaselineScreen(title: "Sleep") { … }                                                                        // large title, nothing pinned
BaselineScreen(title: "Settings") {
    Section { card } header: { BaselineSectionLabel(text: "Strap", style: .glass) }                         // pinned by the LazyVStack
}
```

`ScrollView { LazyVStack(alignment: .leading, spacing: cardSpacing, pinnedViews: [.sectionHeaders]) }` on
`BaselineBackground`, horizontal gutter, `.scrollEdgeEffectStyle(.soft, for: .top)`, no
`.toolbarColorScheme` (do not add one anywhere; the three leftover sites in sheets are cuts). `subtitle`
becomes `.navigationSubtitle` when non-nil. `pinned` content must stay ONE row (≤ ~56pt) and there is one
pinned row per screen. A card that relies on `GeometryReader` width (stage bars) keeps its explicit
`.frame(height:)` — the stack is lazy now. Toolbar items go on the screen as usual:

```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) { StrapStatusPill(onPair: { showPair = true }) }        // Home only
    ToolbarItem(placement: .topBarTrailing) { BaselineToolbarLink(systemImage: "gearshape", accessibilityLabel: "Settings") { SettingsScreen() } }
}
```

### `BaselineDaySwitcher` + `.baselineDaySwipe` — `BaselineDaySwitcher.swift` (NEW)

```swift
@State private var day = Calendar.current.startOfDay(for: Date())
BaselineDaySwitcher(selection: $day, earliest: firstStoredNight, style: .glass)   // pinned under the bar
BaselineDaySwitcher(selection: $day, style: .flat)                                // on the page / in a card
.baselineDaySwipe(previous: { step(-1) }, next: { step(1) })                      // on BaselineScreen's content
let key = Repository.localDayKey(day)                                             // the engine's "yyyy-MM-dd" for that day
```

"‹  Wednesday 1 October  ›": the selected calendar day (`Date`, normalised to `startOfDay`), leading
chevron disabled at `earliest` (when given), trailing chevron disabled at `latest` (defaults to today —
never a future day). Centre text defaults to `BaselineDaySwitcher.title(for:now:)` ("Today" /
"Yesterday" / weekday day month; `BaselineDaySwitcherTests`), the same string Home uses for its nav
title; pass `title:` for another form. `.glass` = one `GlassEffectContainer` + one `.glassEffect(.regular,
in: Capsule())`, ink text. `.baselineDaySwipe` is a `simultaneousGesture` drag that fires only when
clearly horizontal (|dx| ≥ 48pt, > 2·|dy|), so vertical scrolling and chart scrubbing are untouched; the
switcher stays the discoverable control.

### `BaselineCard` — `BaselineCards.swift`

```swift
BaselineCard(title: "Readiness") { … }
BaselineCard(title: "Last night", accessory: AnyView(BaselinePill(text: wokeStamp, color: BaselineTheme.textTertiary))) { … }
BaselineCard(padding: 16) { MetricRing(…) }        // ring tile
```

`title: String? = nil`, `subtitle: String? = nil` (kept for compatibility; restyled screens pass nil),
`accessory: AnyView? = nil`, `padding: CGFloat = cardPadding`. White, 28pt continuous, one shadow, no
stroke, no glass. Two tiles side by side: `HStack(alignment: .top, spacing: 12)` (353 − 12) / 2 = 170pt
each at 393pt; stack them with `ViewThatFits` at `dynamicTypeSize.isAccessibilitySize`.

### `BaselineSectionLabel(text:style:)`

`.flat` (default): uppercase caption, tracking 1.2, `textTertiary`, top padding 8. `.glass`: the same
text in ink inside a `.glassEffect(.regular, in: Capsule())`, leading-aligned — ONLY as the `header:` of a
`Section` inside `BaselineScreen` (Settings). If a device shows jank, the downgrade is `style: .flat`.

### `StatCell(label:value:unit:color:dot:)`

```swift
StatCell(label: "Baseline", value: "64", unit: "ms", color: BaselineTheme.hrv)
StatCell(label: "Deep", value: "1h 42m", dot: BaselineTheme.stageColor("deep"))   // value stays ink
```

Value in `stat` + monospaced digits; label caption / tertiary; unit caption / secondary. `dot:` draws a
6pt circle before the label. Rows of two or three inside an `HStack`.

### `BaselinePill(text:color:style:)`

```swift
BaselinePill(text: tier.baselineLabel, color: tier.baselineColor)                 // .flat (default) inside cards
BaselinePill(text: "Calibrating", color: BaselineTheme.textTertiary)
```

Ink text, 6pt dot in `color`, `color.opacity(0.10)` capsule. `.glass` is chrome only (never inside a card,
never inside a toolbar item).

### `BaselineEmptyState(icon:title:message:)`

24pt light glyph in accent on a 56pt `accent @ 0.10` circle; headline title; centred caption message.
Put a `BaselineCTA` under it when there is an action ("Pair strap", "Add a habit").

### `BaselineChevronRow(text:systemImage:dot:accessibilityHint:destination:)`

```swift
BaselineChevronRow(text: "All workouts", accessibilityHint: "Shows every recorded workout") { WorkoutsScreen() }
BaselineChevronRow(text: progressHeadline, systemImage: "chart.line.uptrend.xyaxis", accessibilityHint: "Opens Progress") { ProgressScreen() }
```

A `NavigationLink` row: caption text in `textSecondary`, trailing chevron, whole row tappable, one
combined accessibility element. The visible label is `text` verbatim (`app.buttons["All workouts"]`
resolves). Put a `Divider().overlay(BaselineTheme.hairline)` above it when it closes a card.

### `BaselineBand` — unchanged (`above / inside / below / calibrating`, `positionPhrase`).

### `MetricRing` + `MetricRingScale` — `BaselineRing.swift`

```swift
let r = snapshot.hrv                                    // TodayMetricReading from TodaySnapshot (funnel)
MetricRing(value: r.value,
           domain: MetricRingScale.domain(state: r.state, cfg: Baselines.hrvCfg),   // nil while calibrating → track only
           color: BaselineTheme.hrv, label: "HRV", unit: "ms",
           context: contextText,                        // the ONE funnel sentence, verbatim
           band: r.state.usable ? r.bandLow...r.bandHigh : nil,
           baseline: r.state.usable ? r.baseline : nil,
           tone: bandTone)                              // good / watch / textTertiary, caller computes
// Sleep tab:
MetricRing(value: night.asleepMin, domain: MetricRingScale.sleepDomain(average30: avg),
           color: BaselineTheme.sleep, label: "Asleep", unit: "", context: contextText,
           band: avg.map { ($0 - 30)...($0 + 30) }, baseline: avg, tone: tone,
           size: 168, lineWidth: 12, valueText: durationText, numeralFont: BaselineTheme.hero(36))
```

Geometry: 270° open-bottom gauge (trim 0…0.75 rotated 135°), round caps; track → band arc (colour @ 0.18,
thicker) → value arc (animated `.snappy(0.6)`, none under Reduce Motion) → baseline tick (2 × 14pt, colour
@ 0.5). Above: 6pt dot + `Text(label)` in `label` / `textSecondary`, its OWN accessibility element so
`staticTexts["HRV"]` matches. Centre: numeral (`numeralFont`, ink) + unit caption (omitted when `""`).
Below: optional tone dot + context caption, centred, NO line limit: the sentence carries the number's
context (delta and band position) and is never ellipsised. A carried value's "Woke Mon 28 Sep · +6 ms vs
baseline · inside your band" takes three lines in a 170pt tile at the default size and more at xxLarge+;
the tile grows with it (`HStack(alignment: .top)` tolerates unequal tile heights). The ring + context is
one accessibility element labelled "HRV 64 ms, +6 ms vs baseline · inside your band".

`MetricRingScale` (pure, tested by `MetricRingScaleTests`): `domain(state:cfg:)` = baseline ∓ 3·sigma
(sigma floored at 5% of baseline) clamped to `cfg.minVal…cfg.maxVal`, nil while `!state.usable`;
`sleepDomain(average30:)` = `0…max(540, avg + 60)`; `fraction(_:in:)` clamps 0…1; `numeral(value:valueText:)`
never clamps ("–" for nil). The numeral is always the funnel's number. No view computes a baseline.

### `BaselineSegmentedPicker` / `BaselineRangePicker` — `BaselineRangePicker.swift`

```swift
BaselineSegmentedPicker(options: TrendsSection.allCases, selection: $section,
                        label: { $0.label }, style: .glass)                // Trends' pinned section control
BaselineRangePicker(selection: $range, style: .flat)                     // 7D/30D/90D inside the Trends section content; Compare
BaselineSegmentedPicker(options: JournalOutcome.allCases, selection: $outcome,
                        label: { $0.label }, style: .flat)                // in-card: Journal outcome, Add-habit kind, Compare metric / source
```

Memberwise order: `options, selection, label, accessibilityLabel = nil, style = .glass`. `style` defaults
to `.glass`, so every in-content use MUST pass `.flat` (existing call sites in JournalAddHabitSheet,
JournalEffectsCard and CompareScreen compile unchanged but render glass until their builder adds it).
`.glass` = one `GlassEffectContainer(spacing: 4)` with ONE `.glassEffect(.regular, in: Capsule())` on the
whole control. `.flat` = `fill` track + `fillStroke`. Selected segment: ink text on `accent @ 0.14` capsule
(matched-geometry slide); unselected: `textSecondary`. `BaselineRangeOption` unchanged
(`label` / `subtitle` / `shortLabel`).

### `BaselineChip`, `JournalNumericChip`, `BaselineAddChip` — `BaselineChip.swift`

```swift
BaselineChip(label: "Alcohol", state: answers[id]) { cycle(id) }          // nil / true / false
JournalNumericChip(label: "Caffeine", unit: "cups", state: .value(2)) { onChange($0) }   // API unchanged
BaselineAddChip(title: "Add", wide: items.isEmpty) { showAddHabit = true }
```

Flat capsules, 44pt hit target (h 14 / v 9). nil: card fill + 1pt `inactive` stroke, `textSecondary`;
true: `accent @ 0.12`, bold check in accent, ink; false: `chipFill`, x in tertiary, tertiary text.
`accessibilityValue` yes / no / not answered. `JournalNumericChip`'s magnitude ("Caffeine · 2") is INK,
semibold, monospaced digits: accent text on the yes fill measures ≈ 4.4:1, under the card floor, so the
fill alone carries the yes state. The chips live only here (no `JournalHabitChip` alias any more).
`JournalNumericChip` still formats its magnitude through `JournalLabels.magnitude` (`Screens/Journal/JournalSupport.swift`);
keep that helper. `BaselineFlowLayout` stays in `JournalSupport.swift` (Home and Journal both use it).

### `BaselineCTA`, `GlassCTA`, `BaselineToolbarLink`, `StrapStatusPill` — `BaselineButtons.swift`

```swift
BaselineCTA(title: "Pair strap") { showPair = true }                       // flat .borderedProminent capsule, accent, white label
BaselineCTA(title: "Add a habit", prominent: false) { showAddHabit = true } // flat .bordered capsule
BaselineCTA(title: "Choose a file…", systemImage: "doc") { … }

GlassEffectContainer(spacing: 12) {                                       // Welcome's floating column
    GlassCTA(title: "Pair WHOOP 4.0") { … }                                // .glassProminent, tinted accent
    GlassCTA(title: "Pair WHOOP 5.0 / MG", prominent: false) { … }        // .glass
    Button("Skip for now") { … }.buttonStyle(WelcomeTextButtonStyle())    // text stays .plain
}
GlassCTA(title: "Journal", systemImage: "checklist", fullWidth: false) { showJournal = true }   // Home's floating button
    // place it over the content, e.g. .overlay(alignment: .bottomTrailing) with gutter padding, or as a
    // .safeAreaBar(edge: .bottom) row; it is a floating control, never inside a card

ToolbarItem(placement: .topBarTrailing) { BaselineToolbarLink(systemImage: "gearshape", accessibilityLabel: "Settings") { SettingsScreen() } }
ToolbarItem(placement: .topBarTrailing) { StrapStatusPill(onPair: { showPair = true }) }
```

`BaselineCTA` is the in-card primary action (cards, sheets' bodies): HIG says a control inside content is
not glass. Labels are the visible text verbatim ("Add strap", "Export", "Allow"). `GlassCTA` branches
with if/else over two different `PrimitiveButtonStyle` types; `fullWidth: false` hugs the label. Use it
only for actions that float over the background. `BaselineToolbarLink` is a `NavigationLink` with a
glyph label and an accessibility label; the bar's glass and tint do the rest. `StrapStatusPill` needs
`AppModel` and `LiveState` in the environment (they are, app-wide): paired → dot + battery % (+ bolt
while charging) + sync glyph / spinner, the pill is the sync button gated as Settings' "Sync now",
VoiceOver label "Connected · 84% · Synced 2h ago"; not paired → "Pair" text. Hidden under DEBUG
`-baseline.marketing YES`. Helpers for Home's subtitle: `StrapStatusPill.syncStamp(live:)` ("Synced 2h
ago" / "Syncing…" / "Not synced yet"; `relativeAgo` is NOOP's global in `Strand/Screens/ScreenScaffold.swift`,
do not redeclare it) and `StrapStatusPill.isPaired(live:registry:)` (the same test the pill makes). No
`.glassEffect` inside a toolbar item, ever (the bar is already glass).

### Charts — `BaselineBandChart.swift`

```swift
.chartYAxis { BaselineChartStyle.yAxis() }                       // trailing, 4 ticks, faint grid, caption labels
.chartXAxis { BaselineChartStyle.dayAxis() }                     // "Sep 28", greedy collisions
.chartXAxis { BaselineChartStyle.monthAxis(spansOverAYear: s.spansOverAYear) }   // Progress
.chartPlotStyle { $0.background(.clear) }
AreaMark(...).foregroundStyle(color.opacity(BaselineChartStyle.bandOpacity))
RuleMark(...).foregroundStyle(color.opacity(BaselineChartStyle.baselineOpacity)).lineStyle(.init(lineWidth: 1, dash: [4, 4]))
LineMark(...).lineStyle(.init(lineWidth: BaselineChartStyle.lineWidth))
BarMark(...).foregroundStyle(color.opacity(BaselineChartStyle.barOpacity)).cornerRadius(BaselineChartStyle.barRadius)
PointMark(...).symbol { BaselineChartStyle.selectedPoint(color) }  // the scrubbed night: white, 2pt colour stroke, 10pt
```

`BaselineBarChart(bars:color:average:height:)` and `BandPoint` keep their signatures. `dayAxis()` is the
one day axis (Trends, Compare); the old `TrendsAxis.dayMarks()` shim is gone.
`ProgressTrajectoryChart`'s hollow anchor fills with `BaselineTheme.card`
(`Circle().strokeBorder(color, lineWidth: 2).background(Circle().fill(BaselineTheme.card))`). TodayStageBar
corner radius 4; hypnogram cornerRadius 3.

## Data funnel — `BaselineDays.swift` (already in Components; read-only for screen builders)

`repo.baselineDays` / `repo.baselineToday` / `repo.baselineWeek` / `await repo.baselineNights()` /
`repo.baselineSeries(key:)` are `repo.days` / `today` / `week` / `sleeps` / `series` rebuilt under the
persisted `baseline.dataSource` precedence (strap first by default, so an imported WHOOP export compares
against the strap instead of replacing it). A screen reads these, never `repo.days`, and reloads on
`repo.baselineReloadID(dataSourceRaw:)` paired with `@AppStorage(BaselineDataSource.key)`. Settings → Data
renders `BaselineDataSourceSetting` (a picker over `BaselineDataSource.allCases` with `selection.subtitle`
as its footer). `BaselineDaysTests` cover the engine. This does not change what any card prints; it
changes which source's night a day shows.

## Shell

- `BaselineApp.swift`: `.preferredColorScheme(.light)` (done).
- `BaselineRoot.swift` (Home builder): three tabs with `.tabItem` + `.tag`, `.tint(BaselineTheme.accent)`,
  `.tabBarMinimizeBehavior(isUITesting ? .never : .onScrollDown)` where `isUITesting` = DEBUG
  `CommandLine.arguments.contains("--ui-testing")` (already present; keep it). BaselineUITests must
  append `"--ui-testing"` to every `launchArguments` array (ScreenshotTests, MarketingShots).
- Sheets (`JournalSheet`, JournalAddHabitSheet, SettingsTextSheet, Devices' chooser): system sheet
  chrome, flat bodies, no `.toolbarColorScheme`, no `.preferredColorScheme(.dark)`; field backgrounds
  `card` + `hairline` stroke at radius 14. NOOP's `AddDeviceWizard` is checked on one real screenshot
  under light mode; if StrandPalette has no light variant, present that sheet alone with
  `.preferredColorScheme(.dark)`.

## Checklist for a screen builder

1. Every colour, font, radius through `BaselineTheme`; every secondary line is `caption` / `textTertiary`
   or `textSecondary`; coloured text only inside white cards.
2. Flat pills (`BaselinePill`) and `StatCell`s inside cards; `BaselineCTA` for in-card actions;
   `BaselineSegmentedPicker(style: .flat)` / `BaselineRangePicker(style: .flat)` for in-content pickers.
3. Glass only through `BaselineScreen.pinned` (one row), `BaselineSectionLabel(style: .glass)` (Settings
   headers), `GlassCTA` (Welcome column, Home's Journal button) and the system bars. Never add
   `.glassEffect` to a card, a row, a chip, a toolbar item or a sheet.
4. Rings only via `MetricRing` with `MetricRingScale` over the funnel's `BaselineState`; never a third
   ring on a screen, never a readiness ring.
5. UI-test anchors kept by name: "HRV" (ring label), "Stages", "Habits", "connected", "HRV baseline",
   `buttons["Progress"]` (now the Trends section segment's label — it is a `Button` with that text),
   "All workouts", "Session", "No strap yet", "Add strap", "Baseline reads", "WHOOP export", "CSV export",
   nav titles ("Trends", "Sleep", "Settings"; Home's title is the day name, so a test waits for the
   "HRV" ring label instead of a "Today" title).
6. Verify once with Reduce Transparency + Increase Contrast: pinned controls, status pill, Settings
   headers, Welcome buttons, the Journal button (text on glass is ink and never depends on the blur).
