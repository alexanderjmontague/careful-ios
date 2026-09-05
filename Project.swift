import ProjectDescription

let team = "376WWRBJJZ"
let group = "group.com.alexandermontague.careful"
// The extension bundle ids carry old "Foqos" names because those App IDs already exist on
// the developer account with the right capabilities, and xcodebuild cannot register new
// ones non-interactively. Renaming them is a one-time step in Xcode's Signing pane.
let base: SettingsDictionary = [
  "DEVELOPMENT_TEAM": .string(team),
  "CODE_SIGN_STYLE": "Automatic",
  "SWIFT_VERSION": "5.0",
]

let project = Project(
  name: "Careful",
  options: .options(disableBundleAccessors: true, disableSynthesizedResourceAccessors: true),
  settings: .settings(base: base),
  targets: [
    .target(
      name: "Careful",
      destinations: .iOS,
      product: .app,
      bundleId: "com.alexandermontague.careful",
      deploymentTargets: .iOS("17.0"),
      infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "Careful",
        "NFCReaderUsageDescription": "Careful reads the ID of your card to enroll it and to unlock an app. It never writes to the card.",
        "UILaunchScreen": [:],
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
      ]),
      sources: ["Careful/Sources/**", "Shared/**"],
      resources: ["Careful/Resources/**"],
      entitlements: "Careful/Careful.entitlements",
      dependencies: [.target(name: "CarefulMonitor"), .target(name: "CarefulShield")],
      settings: .settings(base: ["ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"])
    ),
    .target(
      name: "CarefulMonitor",
      destinations: .iOS,
      product: .appExtension,
      bundleId: "com.alexandermontague.careful.FoqosDeviceMonitor",
      deploymentTargets: .iOS("17.0"),
      infoPlist: .extendingDefault(with: [
        "NSExtension": [
          "NSExtensionPointIdentifier": "com.apple.deviceactivity.monitor-extension",
          "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).CarefulMonitorExtension",
        ],
      ]),
      sources: ["CarefulMonitor/**", "Shared/**"],
      entitlements: "CarefulMonitor/CarefulMonitor.entitlements"
    ),
    .target(
      name: "CarefulShield",
      destinations: .iOS,
      product: .appExtension,
      bundleId: "com.alexandermontague.careful.FoqosShieldConfig",
      deploymentTargets: .iOS("17.0"),
      infoPlist: .extendingDefault(with: [
        "NSExtension": [
          "NSExtensionPointIdentifier": "com.apple.ManagedSettingsUI.shield-configuration-service",
          "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).CarefulShieldExtension",
        ],
      ]),
      sources: ["CarefulShield/**"],
      entitlements: "CarefulShield/CarefulShield.entitlements"
    ),
  ]
)
