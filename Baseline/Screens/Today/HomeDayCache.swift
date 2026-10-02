#if os(iOS)
import Foundation

/// Home's per-day memo, so swiping back and forth between days never rebuilds a day's cards twice.
/// Keyed by the selected day, the effort row's logical day, the store's `refreshSeq` and the data-source
/// setting: a new `refreshSeq` (or a Settings → Data change) drops EVERY entry, since every day's
/// baseline is folded from the same table. The night list (`SleepNightBuilder.nights`, one `await` per
/// load) is memoised once per (seq, source) as well, because it is the same for every day. Main-actor
/// only (it is read and written from `TodayScreen.load`); pure otherwise, `HomeDayCacheTests`.
@MainActor
final class HomeDayCache {
    struct Key: Hashable {
        let dayKey: String
        /// NOOP's 04:00-rollover day for the effort row (`TodayDaySelection.logicalKey`).
        let logicalKey: String
        let refreshSeq: Int
        let dataSource: String
        /// The Progress horizon the readiness chevron's sentence is written for.
        let horizon: Int
    }

    /// What one day's cards need, built once.
    struct Entry {
        let snapshot: TodaySnapshot
        /// Today's signals (nil on a past day or when none fired). Stamped with the journal sequence the
        /// confounders were read under, so a journal edit refreshes only this part.
        var signals: TodaySignals?
        var signalsJournalSeq: Int
        let workouts: [TodayWorkout]
        let progressHeadline: String?
    }

    /// The nights every day's sleep card and signals are read from, one list per (seq, source).
    struct Nights {
        let refreshSeq: Int
        let dataSource: String
        let nights: [SleepNight]
    }

    /// Entries kept before the oldest-touched one goes; a fortnight of swiping fits comfortably.
    let limit: Int
    private var entries: [Key: Entry] = [:]
    /// Keys in touch order, oldest first (a small list: `limit` is tens, not thousands).
    private var order: [Key] = []
    private var nights: Nights?
    /// The `refreshSeq` every stored entry was built under; a different one on the next store empties the cache.
    private(set) var refreshSeq: Int?

    init(limit: Int = 32) { self.limit = max(1, limit) }

    var count: Int { entries.count }

    // MARK: Days

    func entry(for key: Key) -> Entry? {
        guard let e = entries[key] else { return nil }
        touch(key)
        return e
    }

    /// Stores (or replaces) a day's entry. A key from a different `refreshSeq` than the stored ones
    /// clears everything first, so no card is ever served from a stale fold.
    func store(_ entry: Entry, for key: Key) {
        invalidateIfStale(seq: key.refreshSeq)
        if entries.updateValue(entry, forKey: key) == nil {
            order.append(key)
            evict()
        } else {
            touch(key)
        }
    }

    /// Replaces the signals of a stored day (a journal edit changes the illness watch's confounders,
    /// nothing else on the screen).
    func updateSignals(_ signals: TodaySignals?, journalSeq: Int, for key: Key) {
        guard var e = entries[key] else { return }
        e.signals = signals
        e.signalsJournalSeq = journalSeq
        entries[key] = e
    }

    // MARK: Nights

    func nights(refreshSeq: Int, dataSource: String) -> [SleepNight]? {
        guard let n = nights, n.refreshSeq == refreshSeq, n.dataSource == dataSource else { return nil }
        return n.nights
    }

    func storeNights(_ list: [SleepNight], refreshSeq: Int, dataSource: String) {
        invalidateIfStale(seq: refreshSeq)
        nights = Nights(refreshSeq: refreshSeq, dataSource: dataSource, nights: list)
    }

    // MARK: Invalidation

    func invalidate() {
        entries.removeAll()
        order.removeAll()
        nights = nil
        refreshSeq = nil
    }

    private func invalidateIfStale(seq: Int) {
        if let current = refreshSeq, current != seq { invalidate() }
        refreshSeq = seq
    }

    private func touch(_ key: Key) {
        if let i = order.firstIndex(of: key) { order.remove(at: i) }
        order.append(key)
    }

    private func evict() {
        while entries.count > limit, let oldest = order.first {
            order.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }
}
#endif
