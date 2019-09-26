/// Describes which mode the driver is in, which dictates
public enum DriverKind {
  case interactive
  case batch
  case moduleWrap
  case frontend
  case autolinkExtract
  case indent
}

extension DriverKind {
  public var usage: String {
    switch self {
    case .autolinkExtract:
      return "swift-autolink-extract"

    case .batch:
      return "swiftc"

    case .frontend:
      return "swift -frontend"

    case .indent:
      return "swift-indent"

    case .interactive:
      return "swiftc"

    case .moduleWrap:
      return "swift-modulewrap"
    }
  }

  public var title: String {
    switch self {
    case .autolinkExtract:
      return "Swift Autolink Extract"

    case .frontend:
      return "Swift frontend"

    case .indent:
      return "Swift Format Tool"

    case .batch, .interactive:
      return "Swift compiler"

    case .moduleWrap:
      return "Swift Module Wrapper"
    }
  }
}
