#if os(iOS)
import Foundation
import Combine
import WhoopStore

// Strap-first data precedence.
//
// NOOP's `Repository.mergeDaily` lets an imported WHOOP export (or an Apple Health import) win field by
// field over the strap's own computed night for the same day, and `Repository.mergeSleep` lets an imported
// sleep session replace the strap's session for the day it ends on. That is right for NOOP, whose history
// usually starts as an import. Baseline's owner imports the official export to CHECK the strap against
// it, not to replace what the strap measured: "I just want to use them to compare data and see the
// accuracy." So every Baseline screen reads its daily rows through ONE funnel, `BaselineReadouts.days(_:)`,
// which rebuilds the table from the per-source rows the engine publishes (`repo.vitalRows`) with the
// precedence the persisted `baseline.dataSource` setting names:
//
//   strapFirst (default)  the strap's own computed row wins field by field wherever it has a value; the
//                         WHOOP export, then Apple Health, fill only the days and fields it did not record.
//   merged                NOOP's own table (`repo.days` / `repo.sleeps`), imports winning, untouched.
//   importOnly            the imports alone (WHOOP export over Apple Health); the strap's rows are dropped.
//                         A debug / compare mode: "what would the export alone have said?"
//
// `BaselineDays` is the pure engine (value types in, value types out; `BaselineDaysTests`). The Repository
// shims at the bottom are the one-token change a screen makes: `repo.days` → `repo.baselineDays`.

// MARK: - Setting

/// The persisted precedence (`baseline.dataSource` in `UserDefaults.standard`).
enum BaselineDataSource: String, CaseIterable, Identifiable {
    case strapFirst, merged, importOnly

    var id: String { rawValue }

    static let key = "baseline.dataSource"
    static let `default`: BaselineDataSource = .strapFirst

    /// A stored raw value → mode; nil or an unknown string is the default.
    static func resolve(_ raw: String?) -> BaselineDataSource {
        raw.flatMap(BaselineDataSource.init(rawValue:)) ?? .default
    }

    /// The mode in effect right now, read from `defaults`.
    static func current(_ defaults: UserDefaults = .standard) -> BaselineDataSource {
        resolve(defaults.string(forKey: key))
    }

    /// Picker row label.
    var label: String {
        switch self {
        case .strapFirst: return "Strap first"
        case .merged: return "Merged"
        case .importOnly: return "Imports only"
        }
    }

    /// The sentence under the picker for the selected mode.
    var subtitle: String {
        switch self {
        case .strapFirst:
            return "Your strap's own nights are the record. A WHOOP export or Apple Health fills only the days and figures the strap did not record."
        case .merged:
            return "The engine's own table: an imported WHOOP export or Apple Health value replaces the strap's for the same night."
        case .importOnly:
            return "Imports alone, for checking. The strap's own nights are left out until you switch back."
        }
    }

    /// The `.task(id:)` key a screen reloads on: the engine's `refreshSeq` AND the mode, so flipping the
    /// setting rebuilds the table without waiting for the next refresh. Pass the view's
    /// `@AppStorage(BaselineDataSource.key)` raw string so SwiftUI re-evaluates the id when it changes.
    static func reloadID(refreshSeq: Int, raw: String) -> String {
        "\(refreshSeq)|\(resolve(raw).rawValue)"
    }
}

/// The tiny view model Settings → Data renders: a picker over `BaselineDataSource.allCases` bound to
/// `selection`, with `selection.subtitle` as the footer. Writes through to `UserDefaults` on every change,
/// so the next `BaselineReadouts.days(_:)` anywhere in the app sees it.
@MainActor
final class BaselineDataSourceSetting: ObservableObject {
    static let key = BaselineDataSource.key
    static let title = "Data source"
    static let options = BaselineDataSource.allCases

    @Published var selection: BaselineDataSource {
        didSet { defaults.set(selection.rawValue, forKey: Self.key) }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selection = BaselineDataSource.current(defaults)
    }

    /// Re-read the stored value (after a launch argument or another writer changed it).
    func reload() {
        let stored = BaselineDataSource.current(defaults)
        if stored != selection { selection = stored }
    }
}

// MARK: - Pure engine

enum BaselineDays {

    /// Fill order among the imported sources: the WHOOP export before Apple Health (the same order
    /// `DailyMetricSource.vitalPriority` ranks them), the engine's local-cache fallback last.
    static let importOrder: [DailyMetricSource] = [.whoopImport, .appleHealth, .localCache]

    /// The daily table under `mode`, oldest → newest, one row per day.
    ///
    /// - `vitalRows`: `repo.vitalRows`, one row per (source, day) BEFORE NOOP's merge.
    /// - `merged`: `repo.days`, NOOP's merged table. Returned verbatim under `.merged`; under `.strapFirst`
    ///   it also supplies anything the per-source rows never carry (activity-file steps, a day with no
    ///   vital row at all), and is the whole answer when `vitalRows` is empty (previews and tests set
    ///   `days` directly).
    static func days(vitalRows: [SourcedDailyMetric], merged: [DailyMetric], mode: BaselineDataSource) -> [DailyMetric] {
        switch mode {
        case .merged:
            return merged
        case .strapFirst:
            guard !vitalRows.isEmpty else { return merged }
            let mergedByDay = Dictionary(merged.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
            var byDay = fold(vitalRows, strap: true)
            for (day, row) in byDay {
                if let m = mergedByDay[day] { byDay[day] = fill(row, from: m) }
            }
            for (day, m) in mergedByDay where byDay[day] == nil { byDay[day] = m }
            return byDay.values.sorted { $0.day < $1.day }
        case .importOnly:
            return fold(vitalRows, strap: false).values.sorted { $0.day < $1.day }
        }
    }

    /// One row per day: the strap's row (when `strap` and it exists) with every import filling its nil
    /// fields in `importOrder`; without a strap row the first import is the base. A source listed twice
    /// for one day keeps its last row (the engine never does this, but a dictionary must decide).
    private static func fold(_ rows: [SourcedDailyMetric], strap: Bool) -> [String: DailyMetric] {
        var strapByDay: [String: DailyMetric] = [:]
        var importsByDay: [String: [SourcedDailyMetric]] = [:]
        for row in rows {
            switch row.source {
            case .noopComputed:
                if strap { strapByDay[row.metric.day] = row.metric }
            case .whoopImport, .appleHealth, .localCache:
                importsByDay[row.metric.day, default: []].append(row)
            }
        }
        var out: [String: DailyMetric] = [:]
        for day in Set(strapByDay.keys).union(importsByDay.keys) {
            var acc = strapByDay[day]
            for source in importOrder {
                guard let imp = importsByDay[day]?.last(where: { $0.source == source })?.metric else { continue }
                acc = acc.map { fill($0, from: imp) } ?? imp
            }
            if let acc { out[day] = acc }
        }
        return out
    }

    /// `winner` keeps every field it carries (a measured zero is a reading); `filler` supplies only the
    /// ones it left nil. Two groups move whole, from one row, so a figure never sits beside another
    /// recorder's companion: the sleep block (total, efficiency, stage minutes, disturbances and the
    /// `sleepHrOnly` caption that describes how those stages were derived) and the raw red/IR PPG pair.
    /// The engine's own two-source rule (`Repository.coalesceDay`) draws the same two groups; this copy
    /// also keeps `avgSdnn`, which that one drops.
    static func fill(_ winner: DailyMetric, from filler: DailyMetric) -> DailyMetric {
        let sleepFromFiller = winner.totalSleepMin == nil && winner.efficiency == nil
            && winner.deepMin == nil && winner.remMin == nil && winner.lightMin == nil
            && winner.disturbances == nil
        let rawSpo2FromFiller = winner.spo2Red == nil && winner.spo2Ir == nil
        return DailyMetric(
            day: winner.day,
            totalSleepMin: sleepFromFiller ? filler.totalSleepMin : winner.totalSleepMin,
            efficiency: sleepFromFiller ? filler.efficiency : winner.efficiency,
            deepMin: sleepFromFiller ? filler.deepMin : winner.deepMin,
            remMin: sleepFromFiller ? filler.remMin : winner.remMin,
            lightMin: sleepFromFiller ? filler.lightMin : winner.lightMin,
            disturbances: sleepFromFiller ? filler.disturbances : winner.disturbances,
            restingHr: winner.restingHr ?? filler.restingHr,
            avgHrv: winner.avgHrv ?? filler.avgHrv,
            recovery: winner.recovery ?? filler.recovery,
            strain: winner.strain ?? filler.strain,
            exerciseCount: winner.exerciseCount ?? filler.exerciseCount,
            spo2Pct: winner.spo2Pct ?? filler.spo2Pct,
            skinTempDevC: winner.skinTempDevC ?? filler.skinTempDevC,
            respRateBpm: winner.respRateBpm ?? filler.respRateBpm,
            steps: winner.steps ?? filler.steps,
            activeKcalEst: winner.activeKcalEst ?? filler.activeKcalEst,
            spo2Red: rawSpo2FromFiller ? filler.spo2Red : winner.spo2Red,
            spo2Ir: rawSpo2FromFiller ? filler.spo2Ir : winner.spo2Ir,
            avgSdnn: winner.avgSdnn ?? filler.avgSdnn,
            skinTempC: winner.skinTempC ?? filler.skinTempC,
            sleepHrOnly: sleepFromFiller ? filler.sleepHrOnly : winner.sleepHrOnly
        )
    }

    // MARK: Sleep sessions

    /// The day a session belongs to: the LOCAL day it ends on, exactly as `SleepNightBuilder.nights`
    /// groups sessions, so "the strap's night for a day" means the same night on every tab.
    static func endDay(_ s: CachedSleepSession) -> String {
        Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(s.endTs)))
    }

    /// The sleep sessions under `mode`, oldest → newest by onset, EVERY session of a winning day kept
    /// (a nap beside its main night survives, as NOOP's `SleepMerge` keeps it).
    ///
    /// - `imported`: the imported sessions (`repo.sleepSessions(from:to:limit:)`, the WHOOP export's and
    ///   the strap's raw blocks under its import id).
    /// - `computed`: the strap's own scored sessions (`repo.computedSleepSessions(from:to:limit:)`).
    /// - `merged`: `repo.sleeps`, NOOP's merge (imported wins per day). Returned verbatim under `.merged`.
    ///
    /// Under `.strapFirst` a day with any computed session keeps ONLY its computed sessions; the import
    /// fills the days the strap has no session on. There is no richness exception here: the strap's night
    /// is the record whether or not an import staged it better. `.importOnly` is the imports alone.
    static func nights(imported: [CachedSleepSession], computed: [CachedSleepSession],
                       merged: [CachedSleepSession], mode: BaselineDataSource,
                       endDay: (CachedSleepSession) -> String = BaselineDays.endDay) -> [CachedSleepSession] {
        switch mode {
        case .merged:
            return merged
        case .importOnly:
            return imported.sorted { $0.effectiveStartTs < $1.effectiveStartTs }
        case .strapFirst:
            var strapDays = Set<String>()
            for s in computed { strapDays.insert(endDay(s)) }
            let filled = imported.filter { !strapDays.contains(endDay($0)) }
            return (computed + filled).sorted { $0.effectiveStartTs < $1.effectiveStartTs }
        }
    }

    // MARK: Series

    /// A `(day, value)` series over `days` for one of NOOP's series keys (`hrv`, `rhr`, `recovery`,
    /// `strain`, `sleep_performance`, …: `Repository.dailyColumn`), oldest → newest, days without the
    /// column skipped. Baseline's replacement for `repo.series(key:source:)` / `repo.exploreSeries`, which
    /// read NOOP's merged caches and so let the import win whatever the setting says.
    static func series(key: String, days: [DailyMetric]) -> [(day: String, value: Double)] {
        days.compactMap { d in Repository.dailyColumn(key: key, day: d).map { (day: d.day, value: $0) } }
    }
}

// MARK: - Funnel

/// The last table `BaselineReadouts.days(_:)` built, so a screen that reads `repo.baselineDays` several
/// times in one load (Today: snapshot, signals, headline) rebuilds it once. Valid while the repository,
/// its `refreshSeq` and the mode are the ones it was built for: `Repository.refresh` is the only writer
/// of `days` / `vitalRows` and bumps `refreshSeq` whenever either changed, so the key cannot go stale in
/// the app. The row counts are a second guard for a preview or test that assigns `days` directly.
@MainActor
private enum BaselineDaysMemo {
    struct Key: Equatable {
        let repo: ObjectIdentifier
        let seq: Int
        let mode: BaselineDataSource
        let dayCount: Int
        let rowCount: Int
    }
    static var key: Key?
    static var value: [DailyMetric] = []
}

extension BaselineReadouts {

    /// THE daily table every Baseline screen reads: `repo.days` rebuilt under the persisted
    /// `baseline.dataSource` precedence (`BaselineDays.days`). Pure over the repository's published caches;
    /// nothing is read from the store. Memoized per (`repo`, `refreshSeq`, `mode`), see `BaselineDaysMemo`.
    @MainActor
    static func days(_ repo: Repository, mode: BaselineDataSource = .current()) -> [DailyMetric] {
        // `.merged` is `repo.days` itself, and so is any mode before the first refresh publishes per-source
        // rows (previews and tests set `days` directly): neither needs a build or a memo entry.
        if mode == .merged || repo.vitalRows.isEmpty {
            return BaselineDays.days(vitalRows: repo.vitalRows, merged: repo.days, mode: mode)
        }
        let key = BaselineDaysMemo.Key(repo: ObjectIdentifier(repo), seq: repo.refreshSeq, mode: mode,
                                       dayCount: repo.days.count, rowCount: repo.vitalRows.count)
        if BaselineDaysMemo.key == key { return BaselineDaysMemo.value }
        let built = BaselineDays.days(vitalRows: repo.vitalRows, merged: repo.days, mode: mode)
        BaselineDaysMemo.key = key
        BaselineDaysMemo.value = built
        return built
    }

    /// The sleep-session list every Baseline screen builds its nights from: `repo.sleeps` under the
    /// persisted precedence. `repo.sleeps` has already let the import replace the strap's session on the
    /// days it covers, so under `.strapFirst` / `.importOnly` both raw lists are read back from the store
    /// over the same window `Repository.refresh` publishes (4000 days); under `.merged` this is
    /// `repo.sleeps` without a read.
    @MainActor
    static func nights(_ repo: Repository, mode: BaselineDataSource = .current(),
                       now: Date = Date()) async -> [CachedSleepSession] {
        guard mode != .merged else { return repo.sleeps }
        let nowTs = Int(now.timeIntervalSince1970)
        let lo = nowTs - 4000 * 86_400, hi = nowTs + 86_400
        let imported = await repo.sleepSessions(from: lo, to: hi, limit: 4000)
        let computed = await repo.computedSleepSessions(from: lo, to: hi, limit: 4000)
        // No store behind the repository (a preview or test that assigned `sleeps` directly): the merged
        // list is the whole answer, exactly as `days(_:)` falls back to `repo.days` without per-source rows.
        if imported.isEmpty, computed.isEmpty, mode == .strapFirst { return repo.sleeps }
        return BaselineDays.nights(imported: imported, computed: computed, merged: repo.sleeps, mode: mode)
    }

    /// A series over the funnel's days for one of NOOP's series keys; see `BaselineDays.series`.
    @MainActor
    static func series(_ repo: Repository, key: String, mode: BaselineDataSource = .current()) -> [(day: String, value: Double)] {
        BaselineDays.series(key: key, days: days(repo, mode: mode))
    }
}

// MARK: - Repository shims (one-token call-site changes)

extension Repository {
    /// `repo.days` through the funnel. Use this, never `days`, on a Baseline screen.
    var baselineDays: [DailyMetric] { BaselineReadouts.days(self) }

    /// `repo.today` through the funnel: the same logical-day resolver (`Repository.resolveToday`, the
    /// 04:00 rollover and the pre-04:00 banked-night carve-out) over `baselineDays`.
    var baselineToday: DailyMetric? {
        let now = Date()
        return Repository.resolveToday(days: baselineDays,
                                       logicalKey: Repository.logicalDayKey(now),
                                       localKey: Repository.localDayKey(now))
    }

    /// `repo.week` through the funnel: the trailing 7 calendar days ending today, oldest → newest.
    var baselineWeek: [DailyMetric] {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date())
        return baselineDays.filter { $0.day >= cutoff }
    }

    /// `repo.sleeps` through the funnel (async: see `BaselineReadouts.nights`).
    func baselineNights() async -> [CachedSleepSession] { await BaselineReadouts.nights(self) }

    /// `repo.series(key:source:)` / `repo.exploreSeries(key:source:)` through the funnel, for the keys
    /// that have a daily column (`hrv`, `rhr`, `recovery`, `strain`, `sleep_performance`, …).
    func baselineSeries(key: String) -> [(day: String, value: Double)] { BaselineReadouts.series(self, key: key) }

    /// The `.task(id:)` key a screen reloads on: `refreshSeq` plus the data-source mode. Pair it with an
    /// `@AppStorage(BaselineDataSource.key)` property in the view so a change in Settings re-runs the task.
    func baselineReloadID(dataSourceRaw: String) -> String {
        BaselineDataSource.reloadID(refreshSeq: refreshSeq, raw: dataSourceRaw)
    }
}
#endif
