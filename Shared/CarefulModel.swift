import FamilyControls
import Foundation
import ManagedSettings

/// A daily window during which an app should be blocked.
/// Weekdays use Calendar's numbering: 1 = Sunday ... 7 = Saturday.
struct CarefulWindow: Codable, Hashable {
  var startMinute: Int
  var endMinute: Int
  var weekdays: Set<Int>

  static let allDay = CarefulWindow(startMinute: 0, endMinute: 24 * 60, weekdays: Set(1...7))

  func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
    let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
    guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else {
      return false
    }
    let nowMinute = hour * 60 + minute

    if startMinute <= endMinute {
      return weekdays.contains(weekday) && nowMinute >= startMinute && nowMinute < endMinute
    }
    // Wraps past midnight: the tail belongs to the previous day's weekday.
    if weekdays.contains(weekday) && nowMinute >= startMinute { return true }
    let previous = weekday == 1 ? 7 : weekday - 1
    return weekdays.contains(previous) && nowMinute < endMinute
  }
}

/// What a blocked item points at. The picker hands back all three kinds; ignoring any of
/// them means a selection silently does nothing — which is how websites went unblocked
/// for the first week.
enum CarefulTarget: Hashable {
  case app(ApplicationToken)
  case web(WebDomainToken)
  case category(ActivityCategoryToken)
}

/// One blocked item — an app, a web domain, or a whole category. Each gets its OWN
/// ManagedSettingsStore so it can be locked and unlocked independently — unlocking Gmail
/// must never expose Instagram. (Named CarefulApp for history; it is really "item".)
struct CarefulApp: Codable, Identifiable, Hashable {
  let id: UUID
  var label: String
  var target: CarefulTarget
  /// nil means blocked around the clock.
  var window: CarefulWindow?

  init(id: UUID = UUID(), label: String, target: CarefulTarget, window: CarefulWindow? = nil) {
    self.id = id
    self.label = label
    self.target = target
    self.window = window
  }

  init(id: UUID = UUID(), label: String, token: ApplicationToken, window: CarefulWindow? = nil) {
    self.init(id: id, label: label, target: .app(token), window: window)
  }

  // Hand-written so items saved before web/category support (which stored a bare
  // `token`) still decode as apps instead of being dropped.
  private enum CodingKeys: String, CodingKey { case id, label, token, webToken, categoryToken, window }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    label = try c.decodeIfPresent(String.self, forKey: .label) ?? "Item"
    window = try c.decodeIfPresent(CarefulWindow.self, forKey: .window)
    if let t = try c.decodeIfPresent(ApplicationToken.self, forKey: .token) {
      target = .app(t)
    } else if let t = try c.decodeIfPresent(WebDomainToken.self, forKey: .webToken) {
      target = .web(t)
    } else if let t = try c.decodeIfPresent(ActivityCategoryToken.self, forKey: .categoryToken) {
      target = .category(t)
    } else {
      throw DecodingError.dataCorruptedError(forKey: .token, in: c, debugDescription: "no token")
    }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(label, forKey: .label)
    try c.encodeIfPresent(window, forKey: .window)
    switch target {
    case .app(let t): try c.encode(t, forKey: .token)
    case .web(let t): try c.encode(t, forKey: .webToken)
    case .category(let t): try c.encode(t, forKey: .categoryToken)
    }
  }

  /// Stable, collision-free store name derived from the id.
  var storeName: ManagedSettingsStore.Name {
    ManagedSettingsStore.Name("careful" + id.uuidString.replacingOccurrences(of: "-", with: ""))
  }

  /// Should this app be shielded at `date`, ignoring any temporary unlock?
  func shouldBlock(at date: Date) -> Bool {
    guard let window else { return true }
    return window.contains(date)
  }
}

/// Shared state. Lives in the App Group so the DeviceActivityMonitor extension —
/// a separate process — reads the same data as the app.
enum CarefulStore {
  static let suiteName = "group.com.alexandermontague.careful"

  /// iOS allows at most 50 named stores per process.
  static let maxApps = 50

  private static var defaults: UserDefaults {
    UserDefaults(suiteName: suiteName) ?? .standard
  }

  private static let appsKey = "careful.apps"
  private static let unlocksKey = "careful.unlocks"
  private static let cardKey = "careful.enrolledCardUID"

  // MARK: - Blocked apps

  static func loadApps() -> [CarefulApp] {
    guard let data = defaults.data(forKey: appsKey),
      let decoded = try? JSONDecoder().decode([CarefulApp].self, from: data)
    else { return [] }
    return decoded
  }

  static func saveApps(_ apps: [CarefulApp]) {
    guard let data = try? JSONEncoder().encode(apps) else { return }
    defaults.set(data, forKey: appsKey)
  }

  // MARK: - Temporary unlocks

  /// Map of app id -> moment the unlock expires.
  static func unlocks() -> [UUID: Date] {
    guard let raw = defaults.dictionary(forKey: unlocksKey) as? [String: Double] else { return [:] }
    return raw.reduce(into: [:]) { result, pair in
      if let id = UUID(uuidString: pair.key) {
        result[id] = Date(timeIntervalSince1970: pair.value)
      }
    }
  }

  static func unlockedUntil(_ id: UUID) -> Date? {
    guard let expiry = unlocks()[id], expiry > Date() else { return nil }
    return expiry
  }

  static func setUnlock(_ id: UUID, until: Date?) {
    var raw = defaults.dictionary(forKey: unlocksKey) as? [String: Double] ?? [:]
    if let until {
      raw[id.uuidString] = until.timeIntervalSince1970
    } else {
      raw.removeValue(forKey: id.uuidString)
    }
    defaults.set(raw, forKey: unlocksKey)
  }

  /// Drop unlocks that have already expired, so the dictionary cannot grow forever.
  static func pruneUnlocks(now: Date = Date()) {
    var raw = defaults.dictionary(forKey: unlocksKey) as? [String: Double] ?? [:]
    let before = raw.count
    raw = raw.filter { Date(timeIntervalSince1970: $0.value) > now }
    if raw.count != before { defaults.set(raw, forKey: unlocksKey) }
  }

  // MARK: - Enrolled NFC card

  /// Hex UID of the enrolled card. We only ever READ the card — never write to it,
  /// so it keeps working with whatever else the user already uses it for.
  static var enrolledCardUID: String? {
    get { defaults.string(forKey: cardKey) }
    set { defaults.set(newValue, forKey: cardKey) }
  }

  static func matchesEnrolledCard(_ uid: String) -> Bool {
    guard let enrolled = enrolledCardUID else { return false }
    return enrolled.compare(uid, options: .caseInsensitive) == .orderedSame
  }
}
