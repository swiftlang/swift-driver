extension String {
  /// Whether this string is a Swift identifier.
  var isSwiftIdentifier: Bool {
    if isEmpty { return false }

    // FIXME: This is a hack. Check the actual identifier grammar here.
    return spm_mangledToC99ExtendedIdentifier() == self
  }
}
