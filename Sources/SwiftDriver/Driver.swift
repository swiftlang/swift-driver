import TSCBasic
import TSCUtility

/// The Swift driver.
public struct Driver {

  enum Error: Swift.Error {
    case invalidDriverName(String)
  }

  /// The kind of driver.
  let driverKind: DriverKind

  /// The arguments with which the driver was invoked.
  let args: [String]

  /// Create the driver with the given arguments.
  public init(args: [String]) throws {
    // FIXME: Determine if we should run as subcommand.

    self.driverKind = try Self.determineDriverKind(args: args)
    self.args = args
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
  public func computeCompilerMode(options: [Option]) -> CompilerMode {
    if driverKind == .interactive {
      return options.contains(where: { $0.isInput }) ? .immediate : .repl
    }

    let requiresSingleCompile = options.contains(.whole_module_optimization) || options.contains(.index_file)

    // FIXME: Handle -enable-batch-mode and -disable-batch-mode flags.

    if requiresSingleCompile {
      return .singleCompile
    }

    return .standardCompile
  }

  /// Run the driver.
  public func run() throws {
    let argsWithoutExecutable = Array(args.dropFirst())

    // We just need to invoke the corresponding tool if the kind isn't Swift compiler.
    guard driverKind.isSwiftCompiler else {
      let swiftCompiler = try getSwiftCompilerPath()
      return try exec(path: swiftCompiler.pathString, args: ["swift"] + argsWithoutExecutable)
    }

    let optionTable = OptionTable(driverKind: driverKind)
    let options = try optionTable.parse(argsWithoutExecutable)

    if options.contains(.help) {
      optionTable.printHelp(usage: driverKind.usage, title: driverKind.title, includeHidden: options.contains(.help_hidden))
      return
    }

    switch computeCompilerMode(options: options) {
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

extension Option {
  /// Returns true if the option is an input.
  var isInput: Bool {
    if case .INPUT = self {
      return true
    }
    return false
  }
}
