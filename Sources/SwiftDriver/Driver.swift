import TSCBasic
import TSCUtility

/// The Swift driver.
public struct Driver {

  enum Error: Swift.Error {
    case invalidDriverName(String)
  }

  /// The kind of driver.
  let driverKind: DriverKind

  /// The option table we're using.
  let optionTable: OptionTable
  /// The set of parsed options.
  let parsedOptions: ParsedOptions

  /// Create the driver with the given arguments.
  public init(args: [String]) throws {
    // FIXME: Determine if we should run as subcommand.

    self.driverKind = try Self.determineDriverKind(args: args)
    self.optionTable = OptionTable()
    self.parsedOptions = try optionTable.parse(Array(args.dropFirst()))
  }

  /// Determine the driver kind based on the command-line arguments.
  public static func determineDriverKind(
    args: [String],
    cwd: AbsolutePath? = localFileSystem.currentWorkingDirectory
  ) throws -> DriverKind {
    // Get the basename of the driver executable.
    let execPath = try cwd.map{ AbsolutePath(args[0], relativeTo: $0) } ?? AbsolutePath(validating: args[0])
    var driverName = execPath.basename

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

  /// Compute the compiler mode based on the options.
  public func computeCompilerMode() -> CompilerMode {
    if driverKind == .interactive {
      return parsedOptions.hasAnyInput ? .immediate : .repl
    }

    let requiresSingleCompile = parsedOptions.contains(.whole_module_optimization) || parsedOptions.contains(.index_file)

    // FIXME: Handle -enable-batch-mode and -disable-batch-mode flags.

    if requiresSingleCompile {
      return .singleCompile
    }

    return .standardCompile
  }

  /// Run the driver.
  public func run() throws {
    // We just need to invoke the corresponding tool if the kind isn't Swift compiler.
    guard driverKind.isSwiftCompiler else {
      let swiftCompiler = try getSwiftCompilerPath()
      return try exec(path: swiftCompiler.pathString, args: ["swift"] + parsedOptions.commandLine)
    }

    if parsedOptions.contains(.help) || parsedOptions.contains(.help_hidden) {
      optionTable.printHelp(usage: driverKind.usage, title: driverKind.title, includeHidden: parsedOptions.contains(.help_hidden))
      return
    }

    switch computeCompilerMode() {
    case .standardCompile:
      break
    case .singleCompile:
      break
    case .repl:
      break
    case .immediate:
      break
    }
  }

  /// Returns the path to the Swift binary.
  func getSwiftCompilerPath() throws -> AbsolutePath {
    // FIXME: This is very preliminary. Need to figure out how to get the actual Swift executable path.
    let path = try Process.checkNonZeroExit(
      arguments: ["xcrun", "-sdk", "macosx", "--find", "swift"]).spm_chomp()
    return AbsolutePath(path)
  }
}
