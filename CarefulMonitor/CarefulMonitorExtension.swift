import DeviceActivity
import ManagedSettings

/// Runs in its own process when a scheduled interval starts or ends. It does one thing:
/// recompute every item from shared storage. Trusting the callback to describe the world
/// is how missed callbacks turn into a whole day unblocked.
class CarefulMonitorExtension: DeviceActivityMonitor {
  override func intervalDidStart(for activity: DeviceActivityName) {
    super.intervalDidStart(for: activity)
    CarefulBlocker.reconcile()
  }

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    CarefulBlocker.reconcile()
  }
}
