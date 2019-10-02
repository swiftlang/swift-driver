import TSCBasic

extension RelativePath {
  /// Retrieve the basename of the relative path without the extension.
  ///
  /// FIXME: Probably belongs in TSC
  var basenameWithoutExt: String {
    if let ext = self.extension {
      return String(basename.dropLast(ext.count + 1))
    }

    return basename
  }
}
