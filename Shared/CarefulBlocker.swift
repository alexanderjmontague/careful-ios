import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import OSLog

private let log = Logger(subsystem: "com.alexandermontague.careful", category: "Blocker")

/// Applies and removes shields, one ManagedSettingsStore per app.
///
/// The design rule that matters: iOS schedule callbacks are unreliable and
/// ManagedSettings is a plain toggle — iOS never asks us whether an app may launch, it
/// just honours whatever we last wrote. So we never rely on a single callback landing.
/// `reconcile()` recomputes the correct state for every app from scratch and is called
/// on launch, on foreground, after every change, and from the monitor extension.
enum CarefulBlocker {

  // MARK: - Single app

  static func shield(_ app: CarefulApp) {
    let store = ManagedSettingsStore(named: app.storeName)
    // One token per store, so the 50-token-per-store cliff is unreachable.
    switch app.target {
    case .app(let t): store.shield.applications = [t]
    // Web shields cover Safari and in-app browsers (WKWebView), so a blocked domain is
    // blocked in QuietSocial too — intended.
    case .web(let t): store.shield.webDomains = [t]
    case .category(let t):
      store.shield.applicationCategories = .specific([t])
      store.shield.webDomainCategories = .specific([t])
    }
    log.info("shielded \(app.label, privacy: .public)")
  }

  static func unshield(_ app: CarefulApp) {
    let store = ManagedSettingsStore(named: app.storeName)
    store.shield.applications = nil
    store.shield.webDomains = nil
    store.shield.applicationCategories = nil
    store.shield.webDomainCategories = nil
    store.clearAllSettings()
    log.info("unshielded \(app.label, privacy: .public)")
  }

  // MARK: - Reconciliation

  /// The desired shield state for one app right now.
  static func shouldShield(_ app: CarefulApp, now: Date = Date()) -> Bool {
    if CarefulStore.unlockedUntil(app.id) != nil { return false }
    return app.shouldBlock(at: now)
  }

  /// Recompute and apply the correct state for every app. Idempotent and cheap, so it
  /// can be called liberally — this is what closes the gap when a schedule callback is
  /// dropped, which iOS does with some regularity.
  @discardableResult
  static func reconcile(now: Date = Date()) -> Int {
    CarefulStore.pruneUnlocks(now: now)
    let apps = CarefulStore.loadApps()
    var changed = 0

    for app in apps {
      if shouldShield(app, now: now) {
        shield(app)
      } else {
        unshield(app)
      }
      changed += 1
    }
    log.info("reconciled \(changed) app(s)")
    return changed
  }

  // MARK: - Temporary unlock

  /// Unlock a single app for `minutes`. Other apps are untouched — that separation is
  /// the whole point of one store per app.
  static func unlock(_ app: CarefulApp, minutes: Int) {
    let expiry = Date().addingTimeInterval(TimeInterval(minutes * 60))
    CarefulStore.setUnlock(app.id, until: expiry)
    unshield(app)
    scheduleRelock(app, at: expiry)
  }

  static func relockNow(_ app: CarefulApp) {
    CarefulStore.setUnlock(app.id, until: nil)
    if shouldShield(app) { shield(app) }
  }

  /// Ask DeviceActivity to wake us when the unlock expires.
  ///
  /// This is best-effort on purpose: the callback may never fire (a known iOS defect).
  /// `reconcile()` on next foreground is the real guarantee, and the expiry timestamp
  /// lives in shared storage so a missed callback still resolves correctly.
  private static func scheduleRelock(_ app: CarefulApp, at expiry: Date) {
    let calendar = Calendar.current
    let name = DeviceActivityName("carefulRelock." + app.id.uuidString)

    // DeviceActivity refuses any interval shorter than 15 minutes, which would leave a
    // 5-minute unlock with no callback at all. Back-date the start so the interval always
    // spans at least 15 minutes while still ENDING exactly at expiry. A start in the past
    // just fires intervalDidStart immediately; reconcile() is idempotent, so that's harmless.
    let minimumSpan: TimeInterval = 15 * 60 + 30
    let start = min(Date(), expiry.addingTimeInterval(-minimumSpan))
    let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
    let schedule = DeviceActivitySchedule(
      intervalStart: calendar.dateComponents(parts, from: start),
      intervalEnd: calendar.dateComponents(parts, from: expiry),
      repeats: false)

    let center = DeviceActivityCenter()
    // Stopping first avoids the documented trap where startMonitoring on an already
    // monitored activity silently calls stopMonitoring and fires intervalDidEnd.
    center.stopMonitoring([name])
    do {
      try center.startMonitoring(name, during: schedule)
    } catch {
      log.error("relock schedule failed: \(error.localizedDescription, privacy: .public)")
    }
  }
}
