import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Draws the screen iOS shows when a blocked app or site is opened.
class CarefulShieldExtension: ShieldConfigurationDataSource {
  override func configuration(shielding application: Application) -> ShieldConfiguration {
    shield(named: application.localizedDisplayName ?? "This app")
  }
  override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
    shield(named: application.localizedDisplayName ?? "This app")
  }
  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    shield(named: webDomain.domain ?? "This site")
  }
  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
    shield(named: webDomain.domain ?? "This site")
  }

  private func shield(named name: String) -> ShieldConfiguration {
    ShieldConfiguration(
      backgroundBlurStyle: .dark,
      backgroundColor: UIColor(red: 0.20, green: 0.36, blue: 0.55, alpha: 1),
      icon: serifIcon("Blocked", pointSize: 44),
      title: .init(text: name, color: .white),
      subtitle: .init(text: "Open Careful and tap your card to unlock it for a little while.",
                      color: UIColor.white.withAlphaComponent(0.85)),
      primaryButtonLabel: .init(text: "OK", color: .black),
      primaryButtonBackgroundColor: .white,
      secondaryButtonLabel: nil)
  }

  /// ShieldConfiguration.Label has no font parameter, so the only way to put a serif on
  /// the block screen is to render the text into the icon slot ourselves.
  private func serifIcon(_ text: String, pointSize: CGFloat) -> UIImage {
    let font = UIFont(name: "TimesNewRomanPS-BoldMT", size: pointSize)
      ?? UIFont.systemFont(ofSize: pointSize, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
    let size = (text as NSString).size(withAttributes: attrs)
    let padded = CGSize(width: ceil(size.width) + 24, height: ceil(size.height) + 12)
    return UIGraphicsImageRenderer(size: padded).image { _ in
      (text as NSString).draw(at: CGPoint(x: 12, y: 6), withAttributes: attrs)
    }
  }
}
