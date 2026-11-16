import Foundation

// The watch's own copy of what it shows: the iPhone's last context and the
// logs made here since, in the watch's App Group so that the complications
// read them too. No key, token or entry is ever on the watch.
enum WatchStore {
  private static let contextKey = "watch.context"
  private static let outboxKey = "watch.outbox"

  private static var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.screendead.penchant") }

  static var context: WatchContext? {
    get { load(contextKey) }
    set { save(newValue, contextKey) }
  }

  static var outbox: [WatchLog] {
    get { load(outboxKey) ?? [] }
    set { save(newValue, outboxKey) }
  }

  static func board(at now: Date = Date()) -> WatchBoard {
    WatchBoard(context: context, outbox: outbox, now: now)
  }

  private static func load<T: Decodable>(_ key: String) -> T? {
    defaults?.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
  }

  private static func save<T: Encodable>(_ value: T?, _ key: String) {
    defaults?.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
  }
}
