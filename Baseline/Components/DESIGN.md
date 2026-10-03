# Baseline design system (light + Liquid Glass)

The single reference for every screen builder. Everything a screen renders comes from the tokens and
components in `Baseline/Components/`; screens never spell a colour, a font size or a corner radius, and
never compute a baseline, band or average (those come from `BaselineReadouts` / `BaselineReadiness` /
the snapshot models). Vocabulary: **HRV / Resting HR / Readiness / Sleep / Effort / Steps / Calories /
Stress / Intensity minutes / Friends / Journal**; never "Strain", "Recovery" or "Coach"; WHOOP only
nominatively; no competitor's feature names in copy ("Active Zone Minutes", "Body Battery", "Stress Monitor",
"Circles", "Activity rings"; "Intensity minutes" is the generic term). Trademark guardrail: at most two
`MetricRing`s on one screen and never three rings anywhere (Home: HRV and Resting HR, each in its own tile);
the Sleep ring lives on the Sleep tab; Readiness is a number on a horizontal track bar (`ReadinessBar`),
Steps, Intensity minutes and Calories are flat horizontal tracks or bars, Friends draws no ring at all. Platform: iOS 26.0 (`project.yml` deployment target for Baseline, BaselineTests,
BaselineUITests). No availability checks anywhere.

## Information architecture (owner decision; overrides the spec's screen list where they conflict)

FOUR tabs: **Home** (`house`), **Trends** (`chart.xyaxis.line`), **Sleep** (`moon.zzz`), **Friends**
(`person.2`, badged with incoming requests + competition invitations, `FriendsStore.badgeCount`). Settings is
a gear in the top-right of the navigation bar on all four (`BaselineToolbarLink` → `SettingsScreen()`).
Journal is NOT a tab. Friends is opt-in: the tab is always there, Home, Trends and Sleep never need an account
(`Baseline/Research/FRIENDS_SPEC.md`).

| Tab | Root | Structure |
|---|---|---|
| Home | `Screens/Today/TodayScreen.swift` (struct name may stay `TodayScreen`; tab label "Home") | Day-by-day: nav title = the selected day (`BaselineDaySwitcher.title(for:)`), `BaselineDaySwitcher(style: .glass)` pinned under the bar, `.baselineDaySwipe` on the content; every card shows THAT day, in this order: the Readiness score on its track (`ReadinessCard`, with the Progress chevron), Signals on today only, HRV + Resting HR rings, that day's steps against the daily goal (`StepsCard`: the count with "of 8,000", ONE flat `GoalTrack`, one line joining the goal status and the 7-day context, the week's bars against the goal; "Steps so far" on today; ALWAYS present: a day nothing counted reads "–" and a history no source ever counted says why and links to Apple Health), that day's Intensity minutes against the week's goal (`IntensityCard`, one track, only once there are minutes to show, or on today as the one ask for an age), that day's heart-rate trace (`HeartRateCard`, only once the strap banked heart rate for the day), that night's sleep (`LastNightCard`), that day's Calories as its own card (`CaloriesCard`: total = resting + active as the hero, ONE flat `CaloriesSplitBar`, resting in `ringTrack` and active in `effort`, the "1,620 resting · 520 active" split line, one context line on the active part; left out with neither part), that day's Stress as time (`StressCard`: "2 h elevated · 7 h calm · 2 h restored", one flat stacked `StressHoursBar`, one sentence against the person's own 14-day typical; never a 0–3 number; only on a day with a scored still hour, no placeholder card), that day's effort + workouts (`EffortCard`; no energy figure, Calories has its own card). A card with nothing to read yet is left out, never drawn as a placeholder (Steps is the one card that always shows). Every card is a `TodayDetailCard` (title, trailing chevron, the whole card the tap target; the two ring tiles carry the chevron in their corner) that opens its metric's `MetricDetailScreen` on the selected day through Home's ONE `navigationDestination(item:)` (`TodayDetail.screen(_:day:)`: the spec with Home's 1D views, the key's `initialRange`); a floating `GlassCTA(title: "Journal", systemImage: "checklist", fullWidth: false)` opens `JournalSheet(day:)` for the selected day; `StrapStatusPill` stays in the toolbar beside the gear |
| Trends | `Screens/Trends/TrendsScreen.swift` | `BaselineSegmentedPicker(style: .glass)` pinned under the bar over THREE sections: "Trends" (the metric charts; the 7D/30D/90D `BaselineRangePicker(style: .flat)` at the top of the section content), "Progress" (`ProgressScreen`'s body embedded as a section, its horizon picker `.flat`), "Habits" (`JournalPatternsView()`). The Trends section's cards, in this order: HRV and Resting HR over their bands (`TrendBandCard`), Effort bars under the Readiness line (`TrendEffortReadinessCard`, which keeps the "All workouts" `BaselineChevronRow` → `WorkoutsScreen()`), Sleep and Steps bars (`TrendBarCard`; Steps only once some day counted steps, against the daily goal), Intensity minutes by ISO week against the weekly goal (`TrendIntensityCard`, only once some day in the weeks drawn recorded heart rate or workout credit), daily Calories bars (`TrendBarCard`, the same per-day figure Home's card and the Calories detail print, `BaselineReadouts.calorieReadings`; today's bar muted and outside the average). Every card's title is a `TrendsCardTitle`: a `NavigationLink` with a chevron into the same `MetricDetailScreen` Home opens (`TodayDetail.spec`), on the detail range nearest the picker (`TrendsRange.detailRange`) |
| Sleep | `Screens/Sleep/SleepScreen.swift` | hero ring (its last row "Sleep over time" → `MetricDetailScreen(spec: SleepDetail.durationSpec())`, whose 1D page is `SleepNightDayView`: Stages + `SleepHeartRateCard`), the Sleep timing card ("Bedtime and wake over time" → `SleepTimingDetailScreen`, then "Set window"), stages, nights → `NightDetailScreen` (hero, Stages, Heart rate while asleep, Night vitals). Detail links are chevron rows, never tappable titles, so the card titles stay plain static texts. |
| Friends | `Screens/Friends/FriendsScreen.swift` | Signed out: the intro (`FriendsIntroView`), nav title "Friends", nothing pinned. Right after sign-in the setup sheet (`FriendsSetupSheet`: name, the 16+ confirmation, per-metric consent, `FriendsConsentView`). Ready: `BaselineSegmentedPicker(style: .glass)` pinned under the bar over TWO segments, "Friends" (requests, the `LeaderboardCard`: behaviour only, head to head as % of each person's OWN goal; then one `FriendWeekCard` per friend, ALPHABETICAL, never by value; muted friends folded into "Muted (n)") and "Compete" (`CompeteSection`: invitations, active and finished competitions on steps, Intensity minutes, active days, nights at the sleep goal or on-time bedtimes; `CompetitionDetailScreen`). Physiology (HRV, resting HR, Readiness) appears only as each person's weekly change against their OWN baseline ("HRV +8 % vs own baseline", neutral ink, never ranked, never a raw value): one person's heart rate is never compared with another's. "Add a friend" (invite / enter a code) is a toolbar menu beside the gear on the Friends segment; `FriendDetailScreen` (This week, Trends, Together, Manage) is pushed from a week card. No rings |

Journal (`Screens/Journal/`) exposes exactly two entry points: `JournalSheet(day: String)` (a sheet:
day label, that day's habit chips, "Add habit", Done) and `JournalPatternsView()` (the effects card(s)
+ dose rows + empty states, built to sit inside Trends' `LazyVStack`). The old `JournalScreen` root is
gone. Settings and everything under it (Devices, Apple Health, Import, Compare, Export,
Profile, Notifications, About) is unchanged in structure, with these additions: Profile's second card,
"Sleep window" (`SettingsSleepWindowCard`), carries the "Sleep goal" stepper under the two times
(`baseline.sleepGoalMinutes`, `BaselineReadouts.SleepGoal`: 5h–10h in 15-minute steps, default 7h 30m,
`settings-sleep-goal`, one caption: the asleep time a night needs to count as a night at the sleep goal in
Friends); Profile carries a third card, "Activity goals" (`SettingsActivityGoalsCard`: the daily step stepper
on `baseline.stepGoal`, 3,000–30,000 in steps of 500 (Friends' floor, so Home's "Goal met" is Friends' goal
day), `settings-step-goal`, one caption, and a chevron row into the "Intensity goal" page,
`SettingsIntensityGoalScreen` › `SettingsIntensityGoalCard`: one stepper on `baseline.intensityGoalMinutes`,
one caption, the heart-rate basis line with a `SettingsIconTile`); a "Friends" section between Notifications
and About (`SettingsFriendsCard`: signed out, one line that Friends is optional; signed in, a row into
`FriendsSharingScreen`, what leaves the phone per metric, sign out and delete account); Data carries
"Recompute heart-rate days" (`IntradayDayStore.reset()`); the Accuracy screen lists Intensity minutes and heart rate from the detail
specs (`AccuracyExtras`; a future row for either key in `MetricAccuracy.all` drops its extra row) and links
both reviews.

Name contracts between builders: `JournalSheet(day:)`, `JournalPatternsView()`, `SettingsScreen()`,
`ProgressScreen()` (may be reused as the embedded Progress section body), `WorkoutsScreen()`, `FriendsScreen()`.
`BaselineRoot` (four tabs, `--tab home|trends|sleep|friends` with `today` / `journal` / `settings` aliases,
`--friends-segment compete` for the Compete segment, `pendingTab "journal"` → home + sheet, a
`baseline://friends/join/CODE` link → the Friends tab with the code) belongs to the Home builder.

Glass budget per tab under this IA: Home = pinned day switcher (1) + floating Journal button (1) +
system bars; Trends = pinned section control (1) + bars; Sleep = bars only; Friends = the pinned
"Friends | Compete" control (1, only once signed in and ready; the intro has nothing pinned) + bars;
Settings = ≤ 8 pinned headers (Strap, Apple Health, Data, Profile, Notifications, Friends, About, plus
Developer in DEBUG builds); a pushed `MetricDetailScreen` (from Home, Trends or Sleep) = its pinned range picker
(`BaselineRangePicker(style: .glass)`, 1D / 7D / 4W / 1Y) (1) + bars, and so does
`SleepTimingDetailScreen` (7D / 4W / 1Y). Only ONE pinned row per screen: Trends' range picker is
therefore `.flat` in the content, not a second bar.

## Principle

Flat light paper (`background`) with opaque white cards carrying the data. Glass ONLY on the layer that
floats above content and refracts what scrolls beneath it: the tab bar, the navigation bar and its
toolbar items (automatic), the one pinned control under the bar (`BaselineScreen.pinned`: Home's day
switcher, Trends' section control, Friends' "Friends | Compete" control), the strap status pill and the gear (toolbar items, so no extra
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
| `code` / `codeField` / `codeSmall` | fixed-width (system monospaced; SF Rounded has no fixed-width face): 34 semibold (large-title curve, capped 1.5×) / 22 semibold (title2 curve, capped 1.5×) / `.footnote` | where each character must be read on its own: the invite code (`InviteSheet`), the code field (`EnterCodeSheet`), the "On the server" JSON. Never for numbers in cards |

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
`.frame(height:)` — the stack is lazy now. A screen with no pinned `Section` headers and a handful of cards
may wrap them in ONE `VStack(spacing: cardSpacing)` so the lazy stack sees a single item. Home and Friends &
sharing do: as separate lazy items their cards were re-placed on every frame (Home during the push into a
card's detail from a past day, Friends & sharing once scrolled), a layout loop at full CPU that the UI suite
caught as query timeouts. Toolbar items go on the screen as usual:

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
ShareLink(item: text) { BaselineCTALabel(title: "Share code", systemImage: "square.and.arrow.up") }
    .baselineCTAStyle()                                                   // a ShareLink that looks like BaselineCTA (prominent: false for .bordered)

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
- `BaselineRoot.swift` (Home builder): four tabs with `.tabItem` + `.tag` (Friends adds
  `.badge(friends.badgeCount)`), `.tint(BaselineTheme.accent)`,
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

## Metrics layer: Readiness score, Steps, Calories, Stress, sleep timing, fitness, accuracy badges

Vocabulary grows to **HRV / Resting HR / Readiness / Sleep / Effort / Steps / Calories / Stress**; the
banned words stay banned. Trademark guardrail restated for this layer: the Readiness score is a NUMBER
with a horizontal track bar (`ReadinessBar`), never a ring, and no screen ever shows three rings.
Every number keeps its context once: the readout structs below carry the baseline / band / average with
the value, and each component prints it in ONE caption. Accuracy is stated with `AccuracyBadge`, from the
literature table in `Baseline/Research/METRIC_ACCURACY.md` (`MetricAccuracy.all`), so a card never
claims more than the evidence does.

### Readouts — `BaselineReadoutsMetrics.swift` (pure; `BaselineReadoutsMetricsTests`)

All of it is `extension BaselineReadouts`, over the funnel's rows (`repo.baselineDays`), the Sleep tab's
`SleepNight`s and NOOP's own engine results. Nothing here recomputes a score the engine stored.

```swift
// Readiness: NOOP's 0–100 composite (DailyMetric.recovery) with NOOP's bands (< 34 low · < 67 watch · else good)
let r = BaselineReadouts.readinessScore(for: day, days: repo.baselineDays,     // nil until the row has a score
                                        strapScores: BaselineReadouts.strapScores(repo.vitalRows))   // the strap's own scores by day (nil = no per-source rows)
r.score, r.scoreText, r.tone (ReadinessTone .good/.watch/.low), r.tone.label ("Good" / "Fair" / "Low": the word says what the colour says),
r.confidence (.calibrating while the HRV baseline is not yet usable for that morning, .building until 14 nights, then .solid),
r.drivers ([ChargeDriver]), r.driversSentence   // only when the score is the strap's own: an imported score keeps its number and gets no drivers
// "Lifted by heart rate variability (+6), held back by resting heart rate (−3)."  (label + points only, never NOOP's verdict text)
BaselineReadouts.readinessCalibrationNights(for: day, days: days)   // "N of 4" while there is no score; nil otherwise
BaselineReadouts.readinessSeedNights                                 // 4
BaselineReadouts.readinessTone(_ score: Double) -> ReadinessTone

// Steps: the day vs the 7- and 30-day averages of the days BEFORE it (missing days excluded, ≥ 3 observed)
let s = await BaselineReadouts.steps(repo, for: day)                 // @MainActor; strap counter → phone → strap estimate, then the funnel's `steps` column
s.steps, s.average7, s.average30, s.observed7, s.observed30, s.recent (7 days ending on `day`, nil = not recorded), s.delta(against:)
BaselineReadouts.steps(for: day, readings: [(day, value)])            // the pure form (tests)
BaselineReadouts.stepReadings(repo, from:, to:)                      // the resolution itself; imports-only keeps the phone's points alone (the strap's computed steps NOOP's resolver appends are filtered out: stepReadings(mode:resolved:funnel:from:to:))
BaselineReadouts.stepsText(8_412) == "8,412"; stepsDeltaText(steps:average:windowLabel:) // "+1,240 vs your 7‑day average" / "On your 7‑day average" (±5%)

// Calories (BaselineActivityReadouts.swift): total = resting (Mifflin–St Jeor from the entered profile; today prorated)
// + active (the strap's heart-rate estimate from IntradayDayStore, else Apple Health's active_kcal, never both);
// rounded to 10, never to the kcal. ONE per-day figure everywhere: Home's CaloriesCard, its 1D view, Trends' bars
// and the Calories detail's hero and range chart all go through caloriesDay (total, or active alone without age/sex)
let c = await BaselineReadouts.calories(repo, profile: profile, for: day)   // c.totalKcal, c.restingKcal, c.activeKcal, c.activeSource, c.activeAverage30
BaselineReadouts.caloriesDay(for:inputs:strapActive:appleActive:mode:dayFraction:)   // the pure day builder
BaselineReadouts.calorieReadings(from:to:inputs:strapActive:appleActive:mode:todayKey:todayFraction:)   // its per-day readings (Trends, the detail)
BaselineReadouts.caloriesText(2_143) == "2,140"
// (legacy `calories(for:days:logicalKey:)` reads the funnel's active_kcal column, NOOP's whole-day estimate; no screen prints it)

// Stress: TIME, never a score. A day's still waking hours against the person's own daytime heart-rate floor (the
// personal lens: NOOP's .baselineRelative once 4 days of daytime HR exist, else "learning"), nil when the strap
// banked no daytime HR. The 0–3 level drives the curve's shape only and is never printed.
let st = await BaselineReadouts.stressDay(repo, for: day)            // @MainActor; today via StressDayCurve.today, past days via StressDayStore
st.elevatedHours, st.calmHours, st.restoredHours, st.movingHours, st.scoredHours, st.lens, st.floorBPM, st.typicalElevatedHours (14-day median, ≥ 5 days)
st.points ([StressCurvePoint]: id/date/level?/moving), st.peakHour, st.sustainedFrom
StressDayStore.shared.facts(repo, days:scoreMissing:)               // past days' hours on their own lens, kept (the typical and the detail's 7D / 4W / 1Y)
StressDayStore.elevatedHours(facts)                                 // the detail's readings: elevated hours of days that may be totalled
BaselineReadouts.stressDay(result: DaytimeStress.Result, day:)       // pure form; nil when nothing was scored
BaselineReadouts.stressSummary(st); stressLevelText(1.4) == "Medium"; stressDomain == 0...3

// Sleep timing: bed / wake per night, 30-night circular averages, SRI-like regularity, the target window
let t = BaselineReadouts.sleepTiming(for: day, nights: nights)       // nights = SleepNightBuilder.nights(…) over the funnel; .dailyMetric nights have no times and are skipped
t.nights ([SleepTiming.Night] day/bed/wake, newest first, ≤ 30), t.averageBedMinutes, t.averageWakeMinutes (minutes after midnight),
t.regularity (0–100 over the last 14 nights; nil under 5 consecutive-night pairs), t.target (SleepWindow), t.nightsInWindow, t.nightsCounted
BaselineReadouts.SleepWindow.stored()  // UserDefaults "baseline.sleepWindow.bedMinutes" / "wakeMinutes", defaults 23:00 / 07:00; .save(), .spanMinutes
BaselineReadouts.clockText(minutes: 1_380) == "11:00 PM"; hourText(minutes: 1_080) == "6 PM" (axis labels: "18" / "18 Uhr" on a 24-hour device, the same locale as clockText)
BaselineReadouts.circularMeanMinutes([1_410, 30]) == 0; noonInterval(bed:wake:)
```

Regularity formula (documented here and in the source): for every pair of CONSECUTIVE nights in the last
14, the share of the noon-to-noon day on which the two nights agree minute by minute about asleep vs
awake, `1 − |A △ B| / 1440`; the mean is rescaled `200·mean − 100` so chance is 0 and identical nights
are 100, clamped and rounded. An 8-hour night that drifts an hour every day scores 83. Only sleep/wake
timing goes in, the part a wearable gets right (`MetricAccuracy` "sleepRegularity": High).

```swift
// Fitness: NOOP's FitnessAgeEngine (Nes 2011) over the 7 CALENDAR days ending on `day` (stricter than NOOP's last-seven-ROWS gate, on purpose: a Progress point never carries nights from the week before; ENGINE_CAPABILITIES.md §5); needs age, sex and 4 nights of resting HR
let f = BaselineReadouts.fitness(repo, profile: profile, for: day)   // @MainActor over ProfileStore; or the pure fitness(for:days:age:sex:waistCm:hasHeightWeight:)
BaselineReadouts.ProfileSet.current()  // UserDefaults "baseline.profileSet": Settings › Profile's "entered" flag (a DOB / sex change or "Use these"); ProfileStore seeds
                                       // 30 / "male" when nothing was set, so until it is true ProgressProfile.lifted(from:entered:) passes nil age and sex, the
                                       // readout is nil and Progress' Fitness card asks for the profile (.needsProfile). Both consumers go through that one resolver.
f.result (FitnessAgeResult: fitnessAge, chronoAge, deltaYears, bandYears 5), f.vo2max (Nes with a waist, else Uth 15.3·HRmax/RHR),
f.vo2IsFallback, f.vo2BandText ("38–48"), f.restingHr (week median), f.rhrNights, f.activeDays (Effort ≥ 30), f.inputs (the checklist)
BaselineReadouts.fitnessInputs(for:days:age:sex:waistCm:hasHeightWeight:) -> FitnessAgeReadiness   // always available: what is missing
```

### `MetricAccuracy` + `AccuracyBadge` — `MetricAccuracy.swift`

```swift
MetricAccuracy.all                     // 14 rows: key, name, tier (.high/.medium/.low), caveat — verbatim from METRIC_ACCURACY.md
MetricAccuracy.lookup("hrv")?.tier     // .high;  MetricAccuracy["calories"]
AccuracyBadge(metric: "steps")         // a flat pill "Medium accuracy" + info glyph; tap → popover with the caveat (failable: nil for an unrated key)
AccuracyBadge(tier: .low, caveat: "…", name: "Calories")
BaselineCard(title: "Steps", accessory: AccuracyBadge(metric: "steps").map { AnyView($0) }) { StepsTile(readout: s, showsHeader: false) }
```

Flat pill rule: colour @ 0.10 capsule, 6pt dot in the tier colour (High → `good`, Medium → `accent`,
Low → `watch`), text in ink. At accessibility type sizes the pill prints the tier word alone
(`Tier.shortLabel`: "Low"), so it never truncates beside a card title; VoiceOver and the popover keep the
full label. Keys and tiers are pinned by `testMetricAccuracy_coversTheLiteratureTable`.
Change the table in the research doc first, then here.

### `ReadinessBar(score:tone:label:context:)` — `BaselineReadinessBar.swift`

```swift
BaselineCard(title: "Readiness", accessory: AnyView(AccuracyBadge(metric: "readiness"))) {
    if let r { ReadinessBar(score: r.score, tone: r.tone, label: r.tone.label, context: r.driversSentence) }
    else { Text("Readiness after \(BaselineReadouts.readinessSeedNights) nights · \(n) so far") … }
}
```

Numeral in `hero(36)` + "/ 100", the tone's `BaselinePill`, an 8pt `ringTrack` capsule filled to the
score in `good` / `watch` / `low`, ONE context caption under it (never truncated). The track carries NO
marks at NOOP's band edges: ticks at 34 / 67 on a 0–100 bar would reproduce WHOOP's published Recovery
banding (the one trait a bar can still copy from a ring), and in white on `ringTrack` they were barely
visible anyway; the judgement is the pill and the fill's tone, which come from the engine's
`RecoveryScorer.band` through `ReadinessTone`, so no cut point is spelled in a view. One accessibility
element: "Readiness 72 of 100, Good. Lifted by …". `ReadinessTone.baselineColor` gives the same colour
for a dot elsewhere.
This is the form of Readiness everywhere the word is printed: Home's `ReadinessCard`, the morning
summary's subtitle (`TodayReadinessScore.summaryLine`, "Readiness 72 · Good") and both widgets (the
snapshot carries the score, the tone label and the colour name; the extension assembles the same line).
All three read `TodaySnapshot.readinessScore`, resolved once. The seven-night HRV tier survives only as
the HRV tile's week phrase (`TodayReadiness.weekPhrase`, "Week on baseline") and is never called Readiness
on its own.

### `StepsTile` — `BaselineStepsTile.swift`

```swift
StepsTile(readout: s, window: .week)                       // "Steps" header, numeral, "avg 6,000", 7 bars, ONE context line
StepsTile(readout: s, window: .week, showsHeader: false, isToday: isToday)   // inside a BaselineCard(title: StepsTile.title(isToday:), accessory: badge): the card owns the header row
StepsTile(steps: 8_412, average: 6_000, averageLabel: "7‑day", bars: [StepsTile.Bar(id: day, value: 6_000), …])
```

Seven 10pt capsules at 4pt spacing scaled to the week's peak (today solid `steps`, earlier days @ 0.45,
an unrecorded day a 4pt `ringTrack` stub); context = `stepsDeltaText` or "7‑day average after N more
days" or "No steps recorded"; tone dot good (≥ +5%) / watch (≤ −25%) / `steps`. On today (`isToday`)
the count is still accruing, so the header is "Steps so far", the dot stays `steps` and the line reads
"Builds through the day" (plus the "average after N more days" wait while there is none): a partial
count is never judged against whole-day averages, and the average is said once, in the "avg 6,000"
caption. VoiceOver hears the average too: "8,412 steps, 7‑day average 6,000, +2,412 vs your 7‑day
average". On Home the count sits in `StepsCard` (the goal track, `StepsCardBody`) instead; the tile sits beside
Calories or in its own card with `AccuracyBadge(metric: "steps")` in the card's `accessory:` slot and
`showsHeader: false`, so the badge sits in the header row and never beside the hero numeral.

### `StressCurveChart(points:height:accessibilitySummary:)` — `BaselineStressChart.swift`

Swift Charts area (`stress` @ `bandOpacity`) + line (`stress`, `lineWidth`) over 06:00–22:00 of the
day, unscored windows break the line, moving windows are shaded in `fill`, a dashed rule at the elevated
edge (`StressState.elevatedFloor`). No numbers on the y axis: three faint `stress` bands
(`StressCurveChart.bands`, cut at `StressState.restoredCeiling` / `elevatedFloor`, tints 0.04 / 0.08 / 0.13)
named Restored / Calm / Elevated at their midpoints, the words the Stress card's hours use, so the axis and
the card never disagree; x labels every four hours. Pass `BaselineReadouts.stressSummary(st)` as the
summary. Pair with `AccuracyBadge(metric: "stress")` (Low) and the caption "Estimated from heart rate;
N hours left out while you were moving".

### `TimingStripChart(nights:target:averageBed:averageWake:accessibilitySummary:)` — `BaselineTimingStrip.swift`

```swift
TimingStripChart(nights: t.nights.prefix(14).reversed(), target: t.target,
                 averageBed: t.averageBedMinutes, averageWake: t.averageWakeMinutes)
```

One 6pt row per night (oldest at the top, 9pt pitch) over a noon-to-noon axis: the target window as a
`sleep @ 0.12` band, each night's bed → wake capsule in `sleep` (solid inside the window ± 30 min at both
ends, @ 0.45 outside), dashed ticks at the average bed and wake. The axis labels are hours in the
device's clock style (`BaselineReadouts.hourText`: "6 PM · 12 AM · 6 AM · 12 PM", or "18 · 00 · 06 · 12"
on a 24-hour device, the same locale as the card's `clockText` cells), each centred under its tick by its
own width, the last ending at the trailing edge, the row as tall as the caption font (never a fixed
height or pixel offset); at accessibility sizes only the midnight and trailing labels are drawn. Plain
SwiftUI; one accessibility element with a summary sentence. Put `StatCell`s for "Average bedtime" /
"Average wake" / "Regularity" (`clockText(minutes:)`, `"\(t.regularity)"`) under it, and
`AccuracyBadge(metric: "sleepTiming")` on the card.

### `EffortReadinessChart(points:height:accessibilitySummary:)` — `BaselineEffortReadinessChart.swift`

```swift
let points = repo.baselineDays.suffix(30).compactMap { d in
    BaselineReadouts.localMidnight(of: d.day).map { EffortReadinessPoint(id: d.day, date: $0, effort: d.strain, readiness: d.recovery) }
}
EffortReadinessChart(points: points)
```

Effort as `effort` bars (`barOpacity`, `barRadius`) under a Readiness line in `accent`, ONE 0…100 y axis
(both columns are already 0–100, nothing is rescaled), `BaselineChartStyle` axes, a two-dot legend below.
A bar and the line point on one day are that morning's score and the effort that followed it. The shared
axis is for reading, not comparing: never count days where one series "beat" the other (the scales are
unrelated, and it is WHOOP's day reading renamed); a sentence relating them states the lag, effort on
day D against readiness on D+1 (`TrendsSeries.MorningAfter`). The default accessibility summary averages
both series; pass a better sentence when the card has one.

### Tokens added

| Token | Value | Use |
|---|---|---|
| `stress` | `#6D28D9` (6.9 / 6.3) | the Stress curve's line and area |
| `steps` | `#1D4ED8` (6.3 / 5.8) | Steps bars and the Steps header dot |

Calories reuse `effort` (energy is amber); Readiness uses the judgement colours through `ReadinessTone`.

## Metric detail layer: ranges (1D / 7D / 4W / 1Y), the intraday day, Intensity minutes

Four additive pieces in `Baseline/Components/`, pure where they compute and `@MainActor` only where they
read the repository (`MetricSeriesTests`, `IntensityMinutesTests`). Vocabulary unchanged; "Intensity
minutes" is the generic term and no vendor's feature name appears in copy. Nothing here draws a ring.

### `MetricRange`, `MetricKey`, `MetricSeries` — `BaselineReadoutsRanges.swift`

```swift
MetricRange.allCases.map(\.label)   // "1D" "7D" "4W" "1Y"; .days 1 / 7 / 28 / 365; .bucket .day except 1Y = .week (ISO, Monday-first, local)
BaselineRangePicker(selection: $range, style: .glass)       // MetricRange is a BaselineRangeOption (shortLabel == label: "1D" "7D" "4W" "1Y" at AX sizes too)
MetricKey: hrv, rhr, readiness, sleepDuration, sleepEfficiency, bedtime, wake, steps, effort, calories, stressAvg, intensityMinutes, heartRate
k.name, k.seriesKey (NOOP's daily column or nil), k.isCountLike (bars), k.isClockTime, k.higherIsBetter, k.isIntradayDerived
k.sumsPerBucket (Intensity minutes only: weekly TOTALS against a goal, never a mean of recorded days); range.bucket(for: k) (.week on a sum key's 4W / 1Y), range.sumWeeks (4W 4, 1Y 52)

// The one bucketing function every range goes through (missing days excluded, empty buckets absent, n per point):
BaselineRangeSeries.buckets([MetricDayValue], from:to:bucket: .day | .week | .month) -> [RangePoint { id, date, value, min, max, n, band }]
BaselineRangeSeries.stats([MetricDayValue], from:to:) -> MetricStats { latest, latestDay, average, min, max, count, previousAverage, previousCount; change }
BaselineRangeSeries.bucketStart(of: "2026-02-18", bucket: .week) == "2026-02-16"; bucketEnd; dayCount(from:to:); isoCalendar

// Readings per key (pure), then the series:
let readings = BaselineReadouts.metricReadings(key: .hrv, days: repo.baselineDays, nights: nights, stepReadings: steps, intraday: facts)
let bands = BaselineReadouts.metricBands(key: .hrv, days: days, endKey: today)        // day → MetricBand { baseline, low, high }; HRV / resting HR only
let s = BaselineReadouts.metricSeries(key: .hrv, range: .year, endKey: today, readings: readings, bands: bands)
s.points, s.stats, s.lastBucketPartial ("The newest week is still in progress."), s.startKey … s.endKey
// Through the repository (@MainActor): the funnel, stepReadings, the Sleep tab's nights, IntradayDayStore
let s = await BaselineReadouts.metricSeries(repo, profile: profile, key: .intensityMinutes, range: .fourWeeks, endDay: day, entered: profileSet)  // empty until mayScore
// Sentences (said once): "Averaged 64 ms over the last 7 days, 3 ms above the 7 days before."
// 1D: only the difference, the cells hold both values: "+1,240 vs the day before." / "About the same as the day before." / "No day before to compare."
BaselineReadouts.metricContext(series: s, noun: "HRV", unit: "ms", format: whole)
BaselineReadouts.metricChartSummary(series: s, name: "HRV", unit: "ms", format: whole)   // the chart's one VoiceOver sentence
BaselineReadouts.metricChangeText(+4, format: whole, unit: "ms") == "+4 ms"

// Sum metrics (k.sumsPerBucket): one week builder for Home's Intensity card, Trends' Intensity card and the detail
BaselineRangeSeries.weekTotals([MetricDayValue], from:to:) -> [MetricWeekTotal { id (Monday), date, days [Double?] Mon…Sun, inProgress; total, recordedDays, activeDays, hasData, reached(goal) }]
MetricGoal(value: 150, period: .week)   // .perWeek 150, .perDay 21.4 (the 7D "daily pace")
s.sums: MetricSums { weeks, windowDays, activeDays, dayValue, dayBefore, moderate, vigorous, basis; thisWeek, weeksWithData, weeksAtGoal(goal), averageWeek }
BaselineReadouts.metricWindow(key: .intensityMinutes, range: .fourWeeks, endKey:)   // whole Monday weeks: 4W from the Monday 3 weeks back, 1Y 51
BaselineReadouts.metricSeries(key:range:endKey:readings:dayFacts:)                  // dayFacts: intradayValues(records), the split and basis per day
BaselineReadouts.metricSumHero(series: s, goal: g, noun:, unit: "min", format:, isToday:)   // MetricSumHero { cells, sentence, footnote; cellsText }
BaselineReadouts.metricSumChartSummary(series: s, goal: g, name:, unit:, format:)
```

Rules: 7D and 4W are daily points; 1Y is weekly averages over ISO weeks keyed by the Monday (the same
seven days an Intensity-minutes week sums). `min` / `max` on a point are the lowest and highest DAILY
values inside it (for heart rate, the day's own low and high), never a bucket mean; the stats row is
always over daily values. `change` compares the window's average with the same-length window before
it (≥ 3 days on both sides; a 1D window compares with the day before). Efficiency is a percent;
bedtime is kept as minutes after the previous noon and wake as minutes after midnight
(`MetricKey.isClockTime`, `clockValueText` prints them back), so clock averages never wrap. The data
funnel applies to every daily column; the intraday keys are strap-only facts.

Sum metrics (`MetricKey.sumsPerBucket`, Intensity minutes; steps stay a per-day mean because their norm is
a day): a week is its TOTAL against the weekly goal (`MetricDetailSpec.goal`), never a mean of the days
that recorded. A day the strap scored with nothing credited is 0; only a day with no data at all is
missing (no bar; a week without one reading is no bar and is judged by nobody). 7D keeps the seven daily
bars ending on the selected day, the days before this week's Monday lighter, under a dashed "daily pace
21" rule (goal / 7); hero "This week 112 of 150 min" (Monday → the day) and "Days active 4 of 7". 4W is
four Monday weeks and 1Y fifty-two, one bar per week at its total (the week in progress lighter, "The
lighter bar is this week, still in progress."), the dashed "goal 150" line; hero "Weeks at goal 2 of 4"
(weeks with data whose total reached the goal; a week in progress counts once it has) and "Average week
131 min" (finished weeks with data). Under the cells the split ("38 moderate · 37 vigorous, counted
double"; on 4W / 1Y "Over 4 weeks: …") and the basis line. 1D: "This day" is 0 on a scored day with
nothing credited ("No moderate or vigorous minutes today.", Home's "0 min today"), and today counts from
0 like Home's card; only a finished day with no heart rate (or workout credit) is "–" ("No heart rate
recorded on this day."). Home's track, Trends' "This week" and the 7D hero sum through the same
`weekTotals` (`IntensityWeeklyTests` holds the three to one fixture week).

### `IntradayHeartRate` — `BaselineReadoutsIntraday.swift`

```swift
let t = await BaselineReadouts.intradayHeartRate(repo, for: day)      // nil when the strap banked no heart rate that day
// pure: intradayHeartRate(day:buckets:bucketSeconds:nights:workouts:maxPoints:calendar:)
t.points (≤ 1,440: id/date/bpm/minBpm/maxBpm/conf), t.sleep / t.workouts ([Span] clipped to the day, label "Asleep" / the sport),
t.minBpm, t.maxBpm, t.avgBpm (over every bucket), t.coveredMinutes, t.partial (< 240 min), t.dayStart…t.dayEnd
BaselineReadouts.intradaySummary(t)      // VoiceOver only: "Heart rate: 48 to 162 bpm, average 71; asleep 11:20 PM to 7:05 AM; one workout, Running."
BaselineReadouts.intradayContext(t)      // the 1D hero's visible line, what the cells cannot say: "Partial day: 3h 10m of heart rate · asleep 11:20 PM–7:05 AM · one workout, Running."
BaselineReadouts.downsample(buckets, to: 1_440)
```

Reads `repo.hrBuckets(from:to:bucketSeconds: 60)` over the LOCAL calendar day (never the 8,000-row
`hrSamples` default; `INTRADAY_AND_RANGES.md` §1.4), the night ending that morning and the one starting
that evening, and the workout rows reaching back to the day. `conf < 1` marks a PPG-derived stretch
(WHOOP 5.0 / MG) and is drawn lighter, never another colour.

### `IntensityMinutes` — `IntensityMinutes.swift` (definition: `Research/INTENSITY_MINUTES.md` §5)

```swift
let t = IntensityMinutes.Thresholds.karvonen(restingHr: 52, hrMax: 182)   // moderate ≥ 40 % HRR (104 bpm), vigorous ≥ 60 % (130); nil if reserve ≤ 0
IntensityMinutes.Thresholds.hrMax(zoneSet: profile.hrZoneSet)               // fallback: Zone 3+ moderate, Zone 4+ vigorous (NOOP's %HRmax zones)
IntensityMinutes.thresholds(for: day, days: repo.baselineDays, effortHRmax: profile.effortHRmax, zoneSet: profile.hrZoneSet)  // nil = needs age
// The profile gate (ONE predicate): ProfileStore seeds a 30-year-old, so effortHRmax is never nil by itself. Nothing is scored until a date of
// birth is entered (BaselineReadouts.ProfileSet) or a max HR is set by hand. IntradayDayStore.records scores every day through the gated form,
// so Home, Trends and the detail (any range) cannot disagree; screens quote / key on BaselineReadouts.intensityProfile(profile, entered:).
IntensityMinutes.mayScore(entered: profileSet, hrMaxOverride: profile.hrMaxOverride)
IntensityMinutes.thresholds(for:days:effortHRmax:zoneSet:entered:hrMaxOverride:)   // nil (needs age) unless mayScore
IntensityMinutes.restingReference(for: day, days:)       // median of the last 7 nights' resting HR (≥ 3), else the day's own, else nil
IntensityMinutes.RestingReferences(funnel).reference(for: day)   // the same answer from an index built once (the day store's 730-day ranges)
IntensityMinutes.thresholds(for:references:effortHRmax:zoneSet:entered:hrMaxOverride:)              // gated, over that index
let minutes = IntensityMinutes.minutes(samples: [Sample])   // §5: ≥ 20 samples a minute, median bpm: every day inside the store's 14-day verify window
let minutes = IntensityMinutes.minutes(buckets: [HRBucket]) // bucket means, NO sample floor: only an older day the store computes for the first time
let r = IntensityMinutes.credit(day: day, minutes: minutes, thresholds: t)      // DayResult { moderateMin, vigorousMin, bouts, scoredMinutes, basis; credited = m + 2·v }
IntensityMinutes.bouts(minutes, thresholds: t, rule: .default)                  // BoutRule(minMinutes: 3, gapToleranceMinutes: 1); .tenMinute for the older convention
IntensityMinutes.creditFromWorkouts(day:rows:)           // a CSV-only day: Zone 3 = moderate, Zones 4 + 5 = vigorous, basis .workoutsOnly
IntensityMinutes.weekStart(of: "2026-02-18") == "2026-02-16"; weekDays(ending:) (Monday … day)
IntensityMinutes.goal() / saveGoal(_:)                   // "baseline.intensityGoalMinutes", default 150, 60…600 step 10
t.basis.caption   // "40 % / 60 % of your heart-rate reserve (resting 52, max 182)" / "Zone 3 / Zone 4 of your max heart rate (182), …" / "From workouts only" / "Add your age …"

let r = await BaselineReadouts.intensity(repo, profile: profile, for: day)   // IntensityReadout; entered: defaults to ProfileSet.current()
r.creditedToday, r.moderateMin, r.vigorousMin, r.weekStart, r.weekDays ([Int], Mon … day), r.weekCredited, r.weekGoal, r.weekFraction,
r.weekText ("112 / 150 this week"), r.splitText ("38 moderate · 37 vigorous, counted double"), r.basis, r.scoredMinutes, r.partialDay
BaselineReadouts.IntensityReadout.caveat   // "Minutes near the moderate line and strength sessions are uncertain." (Medium accuracy)
```

Bout rule (documented here and in the source): a bout is a maximal run of moderate-or-above minutes
tolerating gaps of at most ONE consecutive below / unscored minute (the gap minute earns nothing and does
not break the bout); a gap of two or more minutes ends it; a bout is credited only with ≥ 3 qualifying
minutes. There is no ten-minute requirement (WHO 2020 / HHS 2018: any duration counts); `BoutRule.tenMinute`
exists for comparison only. Credit: moderate ×1, vigorous ×2. Day = local calendar day; week = Monday
00:00 → next Monday 00:00 local, whatever the locale's first weekday. The card never shows a ring: Home's
`IntensityCard` is a hero "23 min" with "today" and ONE horizontal track "112 / 150 this week"
(`IntensityTrack(readout:)`; VoiceOver hears "112 of 150 minutes this week", never "slash").

### `IntradayDayStore` — `IntradayDayStore.swift` (the per-day cache)

```swift
let records = await IntradayDayStore.shared.records(repo, profile: profile, days: keys, entered: profileSet, computeStress: false)   // day → IntradayDayRecord; gated (mayScore)
BaselineReadouts.intradayValues(records)   // pure: the Stress means, credited minutes of READING days (recordedIntensity), heart-rate low / mean / high
r.credited, r.moderateMin, r.vigorousMin, r.scoredMinutes, r.basis, r.basisIsScored, r.hrMin / hrAvg / hrMax, r.stressMean, r.stressComputed
r.recorded (IntradayDayRecord.isRecorded: scored minutes or workout credit; Trends' weeks use the same), r.recordedIntensity (recorded && basisIsScored)
r.witness, r.storeIdentity    // what the record was computed from (IntradayWitness over the 60-s buckets) and the store it describes
IntradayDayStore.compute(day:buckets:samples:thresholds:fingerprint:workouts:rule:stress:storeIdentity:now:)   // pure; IntradayDayStore(fileURL:) for tests
IntradayDayStore.workouts(startedOn: day, rows:)   // a workouts-only day is credited from the sessions that STARTED on it, never twice across midnight
IntradayDayStore.shared.reset()                    // Settings › Data › "Recompute heart-rate days"
```

Each day is classified once: an in-memory memo keyed by (dayKey, `refreshSeq`), under a JSON file at
`<Application Support>/Baseline/intraday-days.json` keyed by day, every record stamped with its WITNESS
(`IntradayWitness`: the count, last start and a checksum of the day's 60-second buckets, which are
measured ∪ PPG-derived heart rate), the thresholds' signature and the store identity
(`IntradayDayStore.storeIdentity`: the active read id and the strap's first computed night). Never
`repo.hrFingerprint` as the witness: it counts the measured `hrSample` table only, and a WHOOP 4.0 on v25
firmware or a WHOOP 5.0 / MG banks its seconds as PPG estimates in `ppgHrSample`. TODAY never comes from
the memo (live heart rate lands without a `refreshSeq`): every ask re-reads today's buckets and
recomputes only when they moved. Days inside the last 14 are re-read on every new `refreshSeq` (the
strap re-offloads its 14-day store) and, when their buckets moved, classified from their raw samples
(§5's 20-sample floor, so sparse minutes neither earn credit nor clear the 240-minute partial-day line);
older days with a matching record are trusted without a query until the store identity moves (a backup
restored, the strap's data deleted, another strap or the sample data read), when each is re-read once.
An older day computed for the first time uses its bucket means (no sample floor). A store that cannot be
opened computes and persists nothing. A new age, max-HR override or resting reference re-scores the
days it touches. A day the strap recorded nothing on is a record but not an Intensity reading: the
range series and Trends' weeks both leave it out. Why a file in Application Support
and not UserDefaults or Documents: UserDefaults is loaded whole and rewritten as one plist on every
change (wrong for hundreds of growing records); Documents is what file sharing exposes, and a cache is
not a document; Application Support is private, backed up and recomputable. The Stress detail does not
read these records: its 7D / 4W / 1Y series is elevated HOURS per day from `StressDayStore` (each past
day's hours on its own lens, scored once and kept beside the 14-day typical; a 1Y series reads only days
already scored, never 365 raw days), so no range ever prints the 0–3 level. The record's `stressMean`
(`computeStress`) is no longer asked for by any screen.

### `MetricDetailScreen`, `MetricDetailSpec`, `MetricRangeChart`, `IntradayHRChart` — `MetricDetail.swift`

```swift
NavigationLink { MetricDetailScreen(spec: TodayDetail.spec(.hrv), day: dayKey) } label: { … }   // from any card (Home, Trends): the ONE route table, .standard(key) plus the 1D views (Sleep's night, Effort's workouts, Stress' curve, Intensity's week); day defaults to today
MetricDetailScreen(spec: .standard(.heartRate), day: dayKey, initialRange: .day)
var spec = MetricDetailSpec.standard(.steps); spec.dayView = { day in AnyView(MyStepsDayCard(day: day)) }   // a custom 1D view (any view the caller owns)
MetricDetailSpec(key:, title:, noun:, unit:, color:, higherIsBetter:, accuracyKey:, accuracy: (tier, caveat)?, format:, formatDelta:, bandProvider:, dayView:, about:, goal:, heroTitle:, dayViewReplacesHero:)
spec.goal?()   // a sum metric's live target: MetricGoal(value: IntensityMinutes.goal(), period: .week); re-read on UserDefaults.didChangeNotification
MetricRangeChart(series: s, color: color, selected: $selected, yLabel: spec.format, goal: g, accessibilitySummary: …, accessibilityHint: "Higher is better")
IntradayHRChart(trace: t, color: BaselineTheme.rhr, accessibilitySummary: BaselineReadouts.intradaySummary(t))
```

The screen: `BaselineScreen(title:, titleMode: .inline, pinned: { BaselineRangePicker(selection: $range,
style: .glass) })` (the ONE pinned glass row of a pushed screen), then a hero card (`BaselineCard(title:,
accessory: AccuracyBadge)` with `StatCell`s Latest / Average / Low / High for a range, "This day" / "Day
before" for 1D, and ONE sentence under them saying only what the cells do not: `metricContext` (on 1D the
difference from the day before, never the day's value again), or for heart rate on 1D
`intradayContext` (coverage and spans; the low / mean / high sentence is the chart's VoiceOver label)),
the chart card (1D: `spec.dayView`, else `IntradayHRChart` for heart rate under "Through the day" (its legend reads
the shading; a caption only when nothing is shaded), else NO second card: the hero already is the day's number; 7D / 4W:
`MetricRangeChart` as a line over the personal band when the points carry one or bars for `isCountLike`
keys, a weekly bar an explicit span of its Monday-to-Sunday week (a `.weekOfYear` unit bins on the locale's
week, Sunday first in the US); 1Y: the weekly line with the lows-to-highs envelope; a sum metric draws the week totals
and goal rule above instead of a mean), and "About this metric" (`spec.aboutText`:
the `MetricAccuracy` caveat, or the spec's own). The range chart card is untitled (the pinned pill
already names the window, as on Trends); scrubbing writes "Sep 28 · 64 ms" / "Week of Sep 22 · average
64 ms over 6 days" at its top while a finger is on it. Every chart is one VoiceOver element. `standard(_:)` carries
Baseline's colours (HRV teal, resting HR and heart rate coral, sleep keys indigo, steps slate, effort /
calories / intensity amber, stress violet), formatters (`durationText`, `clockText`, `stepsText`,
`caloriesText`, `effortText`) and accuracy rows; Intensity minutes and heart rate, which the literature
table has no row for, carry an explicit Medium badge with their caveat. Calories' hero and chart are the
per-day total Home's card prints (`calorieReadings`, never the funnel's `active_kcal`). Stress is HOURS:
the hero card is titled "Elevated hours a day" (`heroTitle`) over cells in "h" (half-hour grain, no good /
bad direction, never "of 3"), the range chart is elevated hours of the days that may be totalled, and on
1D the day view (`TodayStressDayView`: the hours against the person's typical, the curve, floor, peak and
caveat, with the badge) IS the page (`dayViewReplacesHero`), so no "This day" cell repeats its numbers.
Calories' 1D is the same: `TodayCaloriesDayView` (total, resting / active split, active context, caveat,
badge) is the page, because the series counts only days with an active estimate and a hero over a
resting-only day would say "No calories recorded" above the card's figure. Steps' and Calories' 1D on
today label a running total "So far" and never set a part day against a whole day before.

Empty and ended-on rules: a window with no points draws the hero with its one sentence ("No days with
heart rate in the last 7 days.", or for Intensity minutes before an age or max HR is set "Add your age or
max heart rate in Settings › Profile.") and NO stat row of dashes and NO chart card, so the fact is said
once. The day trace's area fills from the bottom of its y domain (never from 0 bpm, which would paint
under the axis labels) and its caption appears only when there is no shading; the legend ("Asleep",
"Workout") already reads the shading. A Home card opens its detail on the day its number belongs to
(`TodayDetail.detailDay`): the nightly cards carry the newest night forward on an unsynced morning
("Woke Thu, Oct 1"), so HRV / Resting HR / Sleep / Readiness end on that morning, never on a today whose
1D page would say "No HRV recorded" under the number Home just showed. `TodayDetailCard`'s header keeps
title, accuracy pill and chevron on one line while they fit and drops the pill under the title when they
do not (`ViewThatFits`), so "Intensity minutes" never truncates "Medium accuracy".

### Tokens added

| Token | Value | Use |
|---|---|---|
| `BaselineChartStyle.envelopeOpacity` | metric @ 0.07 | the weekly lows-to-highs envelope; a PPG-derived stretch of the day trace |
| `BaselineChartStyle.mutedBarOpacity` | metric @ 0.45 | a muted bar beside full ones: the Steps tile's earlier days, nights outside the sleep window, the week in progress on Trends' Intensity bars (`TrendsWeekBarChart`) |
