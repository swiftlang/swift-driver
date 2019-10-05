extension String {
  /// Whether this string is a Swift identifier.
  var isSwiftIdentifier: Bool {
    if isEmpty { return false }

    // FIXME: This is a hack. Check the actual identifier grammar here.
    return spm_mangledToC99ExtendedIdentifier() == self
  }
}

extension DefaultStringInterpolation {
  /// Interpolates either the provided `value`, or if it is `nil`, the
  /// `defaultValue`.
  mutating func appendInterpolation<T>(_ value: T?, or defaultValue: String) {
    guard let value = value else {
      return appendInterpolation(defaultValue)
    }
    appendInterpolation(value)
  }
}
