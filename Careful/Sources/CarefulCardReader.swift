import CoreNFC
import Foundation

/// Reads the UID of an NFC card.
///
/// READ ONLY, deliberately. We never write an NDEF payload to the card, because the
/// card is already in use by another app (Bloom) and writing would overwrite its data
/// and can permanently lock some tags read-only. The UID is factory-set silicon that
/// every reader can see, so reading it cannot disturb the card or that other app.
final class CarefulCardReader: NSObject {
  enum Purpose {
    case enroll
    case unlock

    var prompt: String {
      switch self {
      case .enroll: return "Hold your iPhone near the card to enroll it."
      case .unlock: return "Hold your iPhone near the card to unlock."
      }
    }
  }

  var onRead: ((String) -> Void)?
  var onError: ((String) -> Void)?

  private var session: NFCTagReaderSession?

  var isAvailable: Bool { NFCTagReaderSession.readingAvailable }

  func begin(_ purpose: Purpose) {
    guard isAvailable else {
      onError?("This device cannot scan NFC tags.")
      return
    }
    session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: nil)
    session?.alertMessage = purpose.prompt
    session?.begin()
  }

  func cancel() {
    session?.invalidate()
    session = nil
  }

  /// Pull the UID out of whichever tag family turned up. No writes anywhere.
  private func uid(of tag: NFCTag) -> String? {
    switch tag {
    case .miFare(let t): return t.identifier.carefulHex
    case .iso7816(let t): return t.identifier.carefulHex
    case .iso15693(let t): return t.identifier.carefulHex
    case .feliCa(let t): return t.currentIDm.carefulHex
    @unknown default: return nil
    }
  }
}

extension CarefulCardReader: NFCTagReaderSessionDelegate {
  func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

  func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
    let code = (error as? NFCReaderError)?.code
    // The user closing the sheet is not a failure worth reporting.
    if code != .readerSessionInvalidationErrorUserCanceled {
      DispatchQueue.main.async { self.onError?(error.localizedDescription) }
    }
    self.session = nil
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
    guard let tag = tags.first else { return }
    session.connect(to: tag) { error in
      if let error {
        session.invalidate(errorMessage: "Could not read the card: \(error.localizedDescription)")
        return
      }
      guard let uid = self.uid(of: tag), !uid.isEmpty else {
        session.invalidate(errorMessage: "That card has no readable ID.")
        return
      }
      session.alertMessage = "Card read."
      session.invalidate()
      DispatchQueue.main.async { self.onRead?(uid) }
    }
  }
}

extension Data {
  var carefulHex: String { map { String(format: "%02X", $0) }.joined() }
}
