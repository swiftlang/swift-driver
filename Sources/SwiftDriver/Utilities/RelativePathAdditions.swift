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
  
  /// Retrieve the basename of the relative path without any extensions,
  /// even if there are several, and without any leading dots. Roughly
  /// equivalent to the regex `/[^.]+/`.
  var basenameWithoutAllExts: String {
    firstBasename(of: basename)
  }
}

extension AbsolutePath {
  /// Retrieve the basename of the relative path without any extensions,
  /// even if there are several, and without any leading dots. Roughly
  /// equivalent to the regex `/[^.]+/`.
  var basenameWithoutAllExts: String {
    firstBasename(of: basename)
  }
}

fileprivate func firstBasename(of name: String) -> String {
  var copy = name[...]
  
  // Remove leading dots, as in dotfiles.
  if let i = copy.firstIndex(where: { $0 != "." }) {
    copy.removeSubrange(..<i)
  }
  
  // Truncate at the first (obviously non-leading) dot.
  if let i = copy.firstIndex(of: ".") {
    copy.removeSubrange(i...)
  }

  return String(copy)
}
