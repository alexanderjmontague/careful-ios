import FamilyControls
import ManagedSettings
import SwiftUI

/// The whole Careful surface: enroll a card, choose apps, and unlock one app at a time.
/// SwiftUI can render every token kind with its real name and icon; it just needs the
/// right overload picked at runtime.
struct TargetLabel: View {
  let target: CarefulTarget
  var body: some View {
    switch target {
    case .app(let t): Label(t)
    case .web(let t): Label(t)
    case .category(let t): Label(t)
    }
  }
}

struct CarefulView: View {
  @State private var apps: [CarefulApp] = CarefulStore.loadApps()
  @State private var enrolledUID: String? = CarefulStore.enrolledCardUID
  @State private var showPicker = false
  @State private var pickerSelection = FamilyActivitySelection()
  @State private var message: String?
  @State private var pendingUnlock: CarefulApp?
  @State private var durationTarget: CarefulApp?
  @State private var durationValue: Double = 5
  @State private var durationInHours = false
  @State private var now = Date()
  @State private var authorized = AuthorizationCenter.shared.authorizationStatus == .approved
  @State private var requestingAuthorization = false

  private let reader = CarefulCardReader()
  private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

  var body: some View {
    NavigationStack {
      List {
        if !authorized { authorizationSection }
        cardSection
        appsSection
      }
      .navigationTitle("Careful")
      .toolbar {
        Button {
          pickerSelection = FamilyActivitySelection()
          showPicker = true
        } label: {
          Image(systemName: "plus")
        }
        .disabled(!authorized || apps.count >= CarefulStore.maxApps)
      }
      .familyActivityPicker(isPresented: $showPicker, selection: $pickerSelection)
      .onChange(of: pickerSelection) { _, selection in addApps(from: selection) }
      .onReceive(tick) { now = $0; refresh() }
      .onAppear { refresh() }
      // Shields are silently ignored until Screen Time access is approved, so ask
      // up front rather than letting the user add apps that never block.
      .task { await requestAuthorizationIfNeeded() }
      .sheet(item: $durationTarget) { app in durationSheet(for: app) }
      .alert(
        "Careful", isPresented: .constant(message != nil),
        actions: { Button("OK") { message = nil } },
        message: { Text(message ?? "") }
      )
    }
  }

  // MARK: - Authorization

  private var authorizationSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        Label("Screen Time access needed", systemImage: "exclamationmark.shield.fill")
          .foregroundStyle(.orange)
        Text("Careful cannot block anything until you allow it to manage Screen Time on this device.")
          .font(.footnote)
          .foregroundStyle(.secondary)
        Button("Allow Screen Time access") {
          Task { await requestAuthorizationIfNeeded(force: true) }
        }
        .buttonStyle(.borderedProminent)
      }
      .padding(.vertical, 4)
    }
  }

  @MainActor
  private func requestAuthorizationIfNeeded(force: Bool = false) async {
    let status = AuthorizationCenter.shared.authorizationStatus
    if status == .approved {
      authorized = true
      return
    }
    guard force || status == .notDetermined else {
      authorized = false
      return
    }
    guard !requestingAuthorization else { return }
    requestingAuthorization = true
    defer { requestingAuthorization = false }
    do {
      try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
      authorized = AuthorizationCenter.shared.authorizationStatus == .approved
      // Anything added before approval was never actually shielded; do it now.
      if authorized { refresh() }
    } catch let error as FamilyControlsError where error == .authorizationConflict {
      authorized = false
      // Only one app can hold this authorization. Say which screen fixes it rather
      // than surfacing Apple's one-liner and leaving the user to guess.
      message = "Another app already has Screen Time access, and iOS only allows one. "
        + "Go to Settings → Screen Time → Apps With Screen Time Access, remove the other app "
        + "(likely Bloom), then come back and tap Allow again."
    } catch {
      authorized = false
      message = "Screen Time access was not granted: \(error.localizedDescription)"
    }
  }

  // MARK: - Card

  private var cardSection: some View {
    Section("Unlock card") {
      if let uid = enrolledUID {
        HStack {
          Label("Card enrolled", systemImage: "checkmark.seal.fill")
            .foregroundStyle(.green)
          Spacer()
          Text(uid.prefix(8) + "…")
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
        }
        Button("Enroll a different card") { enrollCard() }
      } else {
        Button {
          enrollCard()
        } label: {
          Label("Enroll your card", systemImage: "wave.3.right")
        }
        Text("Careful only reads the card's ID. It never writes to it, so a card you already use elsewhere keeps working.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Apps

  private var appsSection: some View {
    Section("Blocked apps") {
      if apps.isEmpty {
        Text("No apps yet. Tap + to choose some.")
          .foregroundStyle(.secondary)
      }
      ForEach(apps) { app in
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            TargetLabel(target: app.target)
              .labelStyle(.titleAndIcon)
            Spacer()
            statusBadge(for: app)
          }

          Text(windowDescription(app))
            .font(.footnote)
            .foregroundStyle(.secondary)

          HStack {
            if CarefulStore.unlockedUntil(app.id) != nil {
              Button("Lock now") {
                CarefulBlocker.relockNow(app)
                refresh()
              }
              .buttonStyle(.borderedProminent)
              .tint(.red)
            } else if CarefulBlocker.shouldShield(app, now: now) {
              Button {
                durationValue = 5
                durationInHours = false
                durationTarget = app
              } label: {
                Label("Unlock", systemImage: "wave.3.right")
                  .foregroundStyle(.blue)
                  .padding(.horizontal, 12)
                  .padding(.vertical, 7)
                  .background(Color(.systemGray5), in: Capsule())
              }
              .buttonStyle(.plain)
              .disabled(enrolledUID == nil)
            }
            Spacer()
            Button(role: .destructive) {
              removeWithCard(app)
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
          }
        }
        .padding(.vertical, 4)
      }
    }
  }

  @ViewBuilder
  private func statusBadge(for app: CarefulApp) -> some View {
    if let until = CarefulStore.unlockedUntil(app.id) {
      let mins = max(0, Int(until.timeIntervalSince(now) / 60) + 1)
      Text("open \(mins)m")
        .font(.caption).foregroundStyle(.orange)
    } else if CarefulBlocker.shouldShield(app, now: now) {
      Image(systemName: "lock.fill").foregroundStyle(.secondary)
    } else {
      Image(systemName: "lock.open").foregroundStyle(.tertiary)
    }
  }

  private func windowDescription(_ app: CarefulApp) -> String {
    guard let window = app.window else { return "Blocked all the time" }
    func clock(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
    return "Blocked \(clock(window.startMinute))–\(clock(window.endMinute))"
  }

  // MARK: - Unlock duration

  private var chosenMinutes: Int {
    let v = Int(durationValue.rounded())
    return durationInHours ? v * 60 : v
  }

  private var durationLabel: String {
    let v = Int(durationValue.rounded())
    let unit = durationInHours ? (v == 1 ? "hour" : "hours") : (v == 1 ? "minute" : "minutes")
    return "\(v) \(unit)"
  }

  private func durationSheet(for app: CarefulApp) -> some View {
    NavigationStack {
      VStack(spacing: 24) {
        TargetLabel(target: app.target).labelStyle(.titleAndIcon).font(.title3)

        VStack(spacing: 6) {
          Text(durationLabel)
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .monospacedDigit()
          Text("It locks again on its own when this runs out.")
            .font(.footnote).foregroundStyle(.secondary)
        }

        Slider(value: $durationValue, in: durationInHours ? 1...12 : 1...60, step: 1)

        Picker("Unit", selection: $durationInHours) {
          Text("Minutes").tag(false)
          Text("Hours").tag(true)
        }
        .pickerStyle(.segmented)
        .onChange(of: durationInHours) { _, hours in
          // Keep the slider inside the new range when the unit flips.
          durationValue = hours ? 1 : 5
        }

        Spacer()

        Button {
          let minutes = chosenMinutes
          durationTarget = nil
          unlock(app, minutes: minutes)
        } label: {
          Label("Tap card to unlock", systemImage: "wave.3.right")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }
      .padding(24)
      .navigationTitle("Unlock for how long?")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { durationTarget = nil }
        }
      }
    }
    .presentationDetents([.medium])
  }

  // MARK: - Actions

  private func refresh() {
    CarefulBlocker.reconcile()
    apps = CarefulStore.loadApps()
    enrolledUID = CarefulStore.enrolledCardUID
  }

  private func addApps(from selection: FamilyActivitySelection) {
    let targets: [CarefulTarget] =
      selection.applicationTokens.map { .app($0) }
      + selection.webDomainTokens.map { .web($0) }
      + selection.categoryTokens.map { .category($0) }
    guard !targets.isEmpty else { return }
    var current = CarefulStore.loadApps()
    for target in targets {
      guard !current.contains(where: { $0.target == target }) else { continue }
      guard current.count < CarefulStore.maxApps else { break }
      current.append(CarefulApp(label: "Item", target: target))
    }
    CarefulStore.saveApps(current)
    refresh()
  }

  private func remove(_ app: CarefulApp) {
    CarefulBlocker.unshield(app)
    CarefulStore.setUnlock(app.id, until: nil)
    CarefulStore.saveApps(CarefulStore.loadApps().filter { $0.id != app.id })
    refresh()
  }

  /// Deleting a blocker is as good as unlocking it forever, so it costs the same: the card.
  private func removeWithCard(_ app: CarefulApp) {
    guard enrolledUID != nil else {
      message = "Enroll your card first — removing a blocker requires it."
      return
    }
    reader.onRead = { uid in
      if CarefulStore.matchesEnrolledCard(uid) {
        remove(app)
      } else {
        message = "That is not the enrolled card."
      }
    }
    reader.onError = { message = $0 }
    reader.begin(.unlock)
  }

  private func enrollCard() {
    reader.onRead = { uid in
      CarefulStore.enrolledCardUID = uid
      enrolledUID = uid
      message = "Card enrolled. Nothing was written to it."
    }
    reader.onError = { message = $0 }
    reader.begin(.enroll)
  }

  /// Unlocking requires the enrolled card — that is the entire point of the physical key.
  private func unlock(_ app: CarefulApp, minutes: Int) {
    pendingUnlock = app
    reader.onRead = { uid in
      guard let target = pendingUnlock else { return }
      pendingUnlock = nil
      if CarefulStore.matchesEnrolledCard(uid) {
        CarefulBlocker.unlock(target, minutes: minutes)
        refresh()
      } else {
        message = "That is not the enrolled card."
      }
    }
    reader.onError = { message = $0; pendingUnlock = nil }
    reader.begin(.unlock)
  }
}
