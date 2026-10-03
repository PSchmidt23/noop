import Foundation

/// The demo backend's fixed cast and its deterministic numbers (FRIENDS_SPEC.md §5.5). Every value is a pure
/// function of (person, day key), so the same day always renders the same board, in screenshots and in tests.
enum LocalDemoFriendsSeed {

    // MARK: Fixed ids (stable across launches)

    static let meID = UUID(uuidString: "BA5E0000-0000-4000-8000-000000000001")!
    static let alexID = UUID(uuidString: "BA5E0000-0000-4000-8000-0000000000A1")!
    static let jordanID = UUID(uuidString: "BA5E0000-0000-4000-8000-0000000000A2")!
    static let priyaID = UUID(uuidString: "BA5E0000-0000-4000-8000-0000000000A3")!
    static let samID = UUID(uuidString: "BA5E0000-0000-4000-8000-0000000000A4")!
    static let chrisID = UUID(uuidString: "BA5E0000-0000-4000-8000-0000000000A5")!
    static let caseyID = UUID(uuidString: "BA5E0000-0000-4000-8000-0000000000A6")!

    static let activeCompetitionID = UUID(uuidString: "BA5E0000-0000-4000-8000-0000000000C1")!
    static let invitationCompetitionID = UUID(uuidString: "BA5E0000-0000-4000-8000-0000000000C2")!
    static let finishedCompetitionID = UUID(uuidString: "BA5E0000-0000-4000-8000-0000000000C3")!

    // MARK: Fixed invite codes (all from FriendInviteCode.charset, so they survive normalisation)

    /// Adds Casey as a pending outgoing request ("Waiting for Casey to accept"). The spec's "DEMO2345" contains the
    /// letter O, which the invite alphabet excludes, so it could never be typed; "CASEY234" stands in for it.
    static let caseyCode = "CASEY234"
    /// Raises `invite_expired`.
    static let expiredCode = "XPRDCDE2"
    /// Raises `invite_used`.
    static let usedCode = "USEDCDE2"
    /// The first code `createInvite()` hands out (redeeming your own raises `invite_self`).
    static let firstOwnCode = "MYCQDE22"

    // MARK: The cast

    struct Person: Sendable {
        var id: UUID
        var name: String
        var stepGoal: Int
        var intensityGoal: Int
        /// The behaviour metrics they share and at which level.
        var shares: [FriendsMetric: ShareAudience]
        /// nil = no physiology; false = calibrating; true = ready.
        var physiologyReady: Bool?
        /// The typical day: steps as a share of their goal, minutes of intensity, chance of a goal night.
        var stepBias: Double
        var minutesBias: Double
        var sleepChance: Double
        var bedtimeChance: Double
    }

    static let alex = Person(id: alexID, name: "Alex", stepGoal: 6_000, intensityGoal: 150,
                             shares: [.steps: .friends, .intensity: .friends, .active: .friends, .sleepGoal: .friends,
                                      .bedtime: .friends, .hrv: .friends, .rhr: .friends, .readiness: .friends],
                             physiologyReady: true, stepBias: 1.15, minutesBias: 28, sleepChance: 0.7, bedtimeChance: 0.55)
    static let jordan = Person(id: jordanID, name: "Jordan", stepGoal: 8_000, intensityGoal: 150,
                               shares: [.steps: .competitions, .intensity: .competitions, .sleepGoal: .friends],
                               physiologyReady: nil, stepBias: 1.0, minutesBias: 22, sleepChance: 0.6, bedtimeChance: 0.5)
    static let priya = Person(id: priyaID, name: "Priya", stepGoal: 10_000, intensityGoal: 300,
                              shares: [.steps: .friends, .intensity: .friends, .active: .friends, .sleepGoal: .friends,
                                       .bedtime: .friends],
                              physiologyReady: nil, stepBias: 0.92, minutesBias: 40, sleepChance: 0.8, bedtimeChance: 0.75)
    static let sam = Person(id: samID, name: "Sam", stepGoal: 7_500, intensityGoal: 120,
                            shares: [.steps: .friends, .intensity: .friends, .active: .friends, .hrv: .friends, .rhr: .friends],
                            physiologyReady: false, stepBias: 0.85, minutesBias: 15, sleepChance: 0.5, bedtimeChance: 0.4)
    static let chris = Person(id: chrisID, name: "Chris", stepGoal: 9_000, intensityGoal: 150,
                              shares: [.steps: .friends], physiologyReady: nil,
                              stepBias: 1.0, minutesBias: 20, sleepChance: 0.6, bedtimeChance: 0.5)
    static let casey = Person(id: caseyID, name: "Casey", stepGoal: 8_000, intensityGoal: 150,
                              shares: [.steps: .friends], physiologyReady: nil,
                              stepBias: 1.0, minutesBias: 20, sleepChance: 0.6, bedtimeChance: 0.5)
    /// "You" in demo mode: shares every behaviour metric with friends, plus HRV and resting HR.
    static let me = Person(id: meID, name: "You", stepGoal: 8_000, intensityGoal: 150,
                           shares: [.steps: .friends, .intensity: .friends, .active: .friends, .sleepGoal: .friends,
                                    .bedtime: .friends, .hrv: .friends, .rhr: .friends],
                           physiologyReady: true, stepBias: 1.02, minutesBias: 25, sleepChance: 0.65, bedtimeChance: 0.6)

    static let acceptedFriends = [alex, jordan, priya, sam]

    // MARK: Deterministic values

    /// SplitMix64 over FNV-1a of "name|day|salt": a stable 0…1 draw.
    static func unit(_ name: String, _ day: String, _ salt: String) -> Double {
        var x = UInt64(bitPattern: Int64(FriendsUploadBuilder.stableHash("\(name)|\(day)|\(salt)")))
        x &+= 0x9E3779B97F4A7C15
        var z = x
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(1 << 53)
    }

    /// One day's value for a behaviour metric. Weekends walk a little more and sleep a little longer.
    static func value(_ p: Person, _ metric: FriendsMetric, day: String) -> DailyShare? {
        let weekend: Bool = {
            guard let d = FriendsDates.date(day) else { return false }
            let wd = FriendsDates.calendar.component(.weekday, from: d)
            return wd == 1 || wd == 7
        }()
        switch metric {
        case .steps:
            let ratio = p.stepBias * (0.55 + 0.9 * unit(p.name, day, "steps")) * (weekend ? 1.1 : 1.0)
            let v = Int((Double(p.stepGoal) * ratio / 10).rounded()) * 10
            return DailyShare(day: day, metric: .steps, value: min(v, 60_000), source: p.name == "Priya" ? "phone" : "strap")
        case .intensity:
            let m = Int((p.minutesBias * (0.2 + 1.6 * unit(p.name, day, "intensity"))).rounded())
            return DailyShare(day: day, metric: .intensity, value: min(m, 300))
        case .active:
            let m = value(p, .intensity, day: day)?.value ?? 0
            return DailyShare(day: day, metric: .active, value: m >= 20 ? 1 : 0)
        case .sleepGoal:
            let chance = weekend ? min(1, p.sleepChance + 0.15) : p.sleepChance
            return DailyShare(day: day, metric: .sleepGoal, value: unit(p.name, day, "sleep") < chance ? 1 : 0)
        case .bedtime:
            return DailyShare(day: day, metric: .bedtime, value: unit(p.name, day, "bed") < p.bedtimeChance ? 1 : 0)
        case .hrv, .rhr, .readiness:
            return nil
        }
    }

    /// The finished bedtime competition is a tie on purpose ("Tied 1st"): fixed nights for its week.
    static let finishedBedtimes: [UUID: [Int]] = [
        meID: [1, 1, 0, 1, 1, 1, 0],      // 5
        priyaID: [1, 0, 1, 1, 1, 1, 0],   // 5
        alexID: [0, 1, 0, 1, 0, 1, 0],    // 3
    ]

    /// Daily rows for a person over `days`, for the metrics they share at any level.
    static func days(_ p: Person, days: [String], finishedWeek: [String]) -> [DailyShare] {
        var out: [DailyShare] = []
        for day in days {
            for metric in FriendsMetric.behaviour where p.shares[metric] != nil {
                guard var row = value(p, metric, day: day) else { continue }
                if metric == .bedtime, let i = finishedWeek.firstIndex(of: day), let fixed = finishedBedtimes[p.id] {
                    row.value = fixed[i]
                }
                out.append(row)
            }
        }
        return out
    }

    /// Five weekly physiology rows (oldest first), neutral and small: one person against their own baseline.
    static func trends(_ p: Person, today: String) -> [TrendShare] {
        guard let ready = p.physiologyReady else { return [] }
        let mondays = FriendsUploadBuilder.weeks(today: today).map(\.monday)
        var out: [TrendShare] = []
        for metric in FriendsMetric.physiology where p.shares[metric] != nil {
            if !ready {
                out.append(TrendShare(metric: metric, weekStart: mondays.last ?? today, status: .calibrating))
                continue
            }
            for (i, monday) in mondays.enumerated() {
                let wobble = unit(p.name, monday, metric.rawValue) - 0.5
                let delta: Int
                switch metric {
                case .hrv: delta = i == mondays.count - 1 ? 8 : Int((wobble * 14).rounded())
                case .rhr: delta = i == mondays.count - 1 ? -2 : Int((wobble * 4).rounded())
                default: delta = i == mondays.count - 1 ? 4 : Int((wobble * 8).rounded())
                }
                let band: TrendBand = abs(delta) >= (metric == .hrv ? 12 : metric == .rhr ? 4 : 6)
                    ? (delta > 0 ? .above : .below) : .within
                out.append(TrendShare(metric: metric, weekStart: monday, status: .ready, delta: delta, band: band))
            }
        }
        return out
    }
}
