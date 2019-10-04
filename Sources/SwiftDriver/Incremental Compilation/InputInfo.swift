import TSCBasic
import TSCUtility
import Foundation

public struct InputInfo: Equatable {

  let status: Status
  let previousModTime: Date

  public init(status: Status, previousModTime: Date) {
    self.status = status
    self.previousModTime = previousModTime
  }

  static let newlyAdded = Self(status: .newlyAdded, previousModTime: Date.distantFuture)
}

public extension InputInfo {
  enum Status {
    case upToDate, needsCascadingBuild, needsNonCascadingBuild, newlyAdded

    /// The identifier is used for the tag in the value of the input in the InputInfoMap
    var identifier: String {
    switch self {
    case .upToDate:
      return ""
    case .needsCascadingBuild, .newlyAdded:
      return "!dirty"
    case .needsNonCascadingBuild:
      return "!private"
      }
    }
    public init?(identifier: String) {
      switch identifier {
      case "": self = .upToDate
      case "!dirty": self = .needsCascadingBuild
      case "!private": self = .needsNonCascadingBuild
      default: return nil
      }
    }
  }
}

/// decoding
public extension InputInfo {
  init(tag: String, previousModTime: Date) throws {
    self.init(status: Status(tag: tag),
              previousModTime: previousModTime)
  }
}

fileprivate extension InputInfo.Status {
  init(tag: String) {
  /// The Yams tag can be other values if there is no tag in the file
    self = Self(identifier: tag) ?? Self(identifier: "")!
  }
}
