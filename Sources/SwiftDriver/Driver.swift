#if os(macOS)
import Darwin.C
#else
import Glibc
#endif

/// The Swift driver.
public final class Driver {

  enum Error: Swift.Error {
    case invalidDriverName(String)
  }

  /// The kind of driver.
  let driverKind: DriverKind

  /// Create the driver with the given arguments.
  public init(args: [String]) {
    // FIXME: Determine if we should run as subcommand.

    do {
      driverKind = try Self.determineDriverKind(args: args)
    } catch {
      print("error: \(error)")
      exit(EXIT_FAILURE)
    }
  }

  /// Determine the driver kind based on the command-line arguments.
  static func determineDriverKind(args: [String]) throws -> DriverKind {
    // We always expect to have the first argument. By default, the driver name
    // is used to determine the kind.
    var driverName = args.first!

    // Determine driver kind based on the first argument.
    if args.count > 1 {
      let driverModeOption = "--driver-mode="
      if args[1].starts(with: driverModeOption) {
        driverName = String(args[1].dropFirst(driverModeOption.count))
      } else if args[1] == "-frontend" {
        return .frontend
      } else if args[1] == "-modulewrap" {
        return .moduleWrap
      }
    }

    switch driverName {
    case "swift":
      return .interactive
    case "swiftc":
      return .batch
    case "swift-autolink-extract":
      return .autolinkExtract
    case "swift-indent":
      return .indent
    default:
      throw Error.invalidDriverName(driverName)
    }
  }

  /// Run the driver.
  public func run() {
    let options = OptionTable(driverKind: driverKind)
    options.printHelp(usage: driverKind.usage, title: driverKind.title, includeHidden: false)
  }
}
