#if os(iOS)
  import ActivityKit
  import AppIntents
  import Foundation

  // Compiled into the app and the widget extension: the extension draws the
  // Live Activity (NightWidget.swift), and its +1 runs in the app's process
  // (LiveActivityIntent). Updates are local only: no push token is asked for.
  @available(iOS 17.0, *)
  struct NightAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
      var count: Double
    }

    let start: Date
    let endBy: Date
    // Nil unless the person chose to show the habit on the Lock Screen.
    let habit: String?
    let slot: Int?
  }

  enum NightStore {
    private static let key = "nightOut.night"

    static func load() -> NightRecord? {
      guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
      return try? JSONDecoder().decode(NightRecord.self, from: data)
    }

    static func save(_ night: NightRecord?) {
      let defaults = UserDefaults(suiteName: appGroup)
      if let night, let data = try? JSONEncoder().encode(night) {
        defaults?.set(data, forKey: key)
      } else {
        defaults?.removeObject(forKey: key)
      }
    }
  }

  enum NightError: Error {
    case alreadyRunning
  }

  @available(iOS 17.0, *)
  enum NightOut {
    static var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private static func activity(_ id: String) -> Activity<NightAttributes>? {
      Activity<NightAttributes>.activities.first { $0.id == id }
    }

    private static func live(_ activity: Activity<NightAttributes>) -> Bool {
      activity.activityState == .active || activity.activityState == .stale
    }

    static func start(
      uid: String, viceID: String, habit: String?, slot: Int?, base: Double, now: Date = Date()
    ) throws -> NightRecord {
      if let running = NightStore.load(), let activity = activity(running.id), live(activity),
        !running.over(at: now)
      {
        throw NightError.alreadyRunning
      }
      let endBy = NightPlan.endBy(start: now)
      let activity = try Activity.request(
        attributes: NightAttributes(start: now, endBy: endBy, habit: habit, slot: habit == nil ? nil : slot),
        content: ActivityContent(state: NightAttributes.ContentState(count: base), staleDate: endBy),
        pushType: nil)
      let night = NightRecord(
        id: activity.id, uid: uid, viceID: viceID, start: now, endBy: endBy, showsHabit: habit != nil,
        base: base, outside: [])
      NightStore.save(night)
      return night
    }

    // The record's count onto the Lock Screen; the stale date never moves.
    static func refresh() async {
      guard let night = NightStore.load(), let activity = activity(night.id), live(activity) else { return }
      await activity.update(
        ActivityContent(state: NightAttributes.ContentState(count: night.count), staleDate: night.endBy))
    }

    static func end() async {
      let count = NightStore.load()?.count
      NightStore.save(nil)
      for activity in Activity<NightAttributes>.activities {
        await activity.end(
          ActivityContent(
            state: NightAttributes.ContentState(count: count ?? activity.content.state.count),
            staleDate: activity.attributes.endBy),
          dismissalPolicy: .immediate)
      }
    }

    // A log made outside the app: the +1, a widget, a control or Siri.
    static func noted(_ log: QueuedLog) async {
      guard var night = NightStore.load(),
        night.note(id: log.id, uid: log.uid, viceID: log.viceID, at: log.date)
      else { return }
      NightStore.save(night)
      await refresh()
    }

    static func forget(_ logID: String) async {
      guard var night = NightStore.load(), night.forget(logID) else { return }
      NightStore.save(night)
      await refresh()
    }

    // Ends whatever no longer belongs: a night past its end, of another
    // account or none, one the person removed from the Lock Screen, and any
    // activity that is not the record's. Returns the night still running.
    @discardableResult
    static func tidy(uid: String?, now: Date = Date()) async -> NightRecord? {
      guard let night = NightStore.load(), let uid, night.uid == uid, !night.over(at: now),
        let current = activity(night.id), live(current)
      else {
        await end()
        return nil
      }
      for other in Activity<NightAttributes>.activities where other.id != night.id {
        await other.end(nil, dismissalPolicy: .immediate)
      }
      return night
    }

    // The app's look at the habit's entries since the night started.
    static func reconcile(uid: String?, base: Double, seen: Set<String>) async -> NightRecord? {
      guard var night = await tidy(uid: uid) else { return nil }
      night.reconcile(base: base, seen: seen, queued: Set(LogQueue.read().filter { $0.op == .log }.map(\.id)))
      NightStore.save(night)
      await refresh()
      return night
    }
  }

  // The Lock Screen's +1. It touches only the App Group: the app writes the
  // queued log as it writes a widget's (LogQueue.swift), so the count never
  // waits on the journal key, which may be out of reach while locked.
  @available(iOS 17.0, *)
  struct NightLogIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log one tonight"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Night")
    var nightID: String

    init() {}

    init(nightID: String) {
      self.nightID = nightID
    }

    func perform() async throws -> some IntentResult {
      guard let night = NightStore.load(), night.id == nightID else { return .result() }
      guard !night.over(at: Date()) else {
        await NightOut.end()
        return .result()
      }
      guard let log = LogQueue.log(uid: night.uid, viceID: night.viceID) else { throw LogError.notSaved }
      LastLog.save(LastLog(id: log.id, viceID: log.viceID, at: log.createdAt))
      await NightOut.noted(log)
      reloadEverything()
      return .result()
    }
  }
#endif
