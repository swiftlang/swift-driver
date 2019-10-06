import Foundation

public extension Date {
  init(legacyDriverSecsAndNanos secsAndNanos: [Int]) throws {
  enum Errors: LocalizedError {
    case needSecondsAndNanoseconds
  }
  guard secsAndNanos.count == 2 else {
    throw Errors.needSecondsAndNanoseconds
    }
    self = Self(legacyDriverSecs: secsAndNanos[0], nanos: secsAndNanos[1])
  }
  init(legacyDriverSecs secs: Int, nanos: Int) {
    self = Date(timeIntervalSince1970: Double(secs) + Double(nanos) / 1e9)
  }
}
