import Foundation

/// UIKit may deliver an expired background callback after a newer foreground epoch.
struct EmbeddedRecoveryWindow {
  private(set) var token: UUID?
  mutating func begin() -> UUID {
    let next = UUID()
    token = next
    return next
  }
  mutating func end() { token = nil }
  mutating func expire(_ candidate: UUID) -> Bool {
    guard token == candidate else { return false }
    token = nil
    return true
  }
}
