import SwiftUI

@main
struct CarefulMain: App {
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      CarefulView()
        // Recompute every item whenever we come to the front. This is the safety net
        // for schedule callbacks iOS drops: a missed signal costs seconds, not a day.
        .onChange(of: scenePhase) { _, phase in
          if phase == .active { CarefulBlocker.reconcile() }
        }
    }
  }
}
