import TSCBasic

// We'll need to figure out how to model `Toolchain` to handle different platforms.
//
// Note: This class is not thread-safe.
public final class DarwinToolchain {

  /// Swift compiler path.
  public lazy var swiftCompiler: Result<AbsolutePath, Swift.Error> = Result {
    try xcrunFind(exec: "swift")
  }

  /// SDK path.
  public lazy var sdk: Result<AbsolutePath, Swift.Error> = Result {
    let result = try Process.checkNonZeroExit(
      arguments: ["xcrun", "-sdk", "macosx", "--show-sdk-path"]).spm_chomp()
    return AbsolutePath(result)
  }

  /// Path to the StdLib inside the SDK.
  public func sdkStdlib(sdk: AbsolutePath) -> AbsolutePath {
    sdk.appending(RelativePath("usr/lib/swift"))
  }

  public var resourcesDirectory: Result<AbsolutePath, Swift.Error> {
    // FIXME: This will need to take -resource-dir and target triple into account.
    return swiftCompiler.map{ $0.appending(RelativePath("../../lib/swift/macosx")) }
  }

  public init() {
  }

  /// Utility function to lookup an executable using xcrun.
  private func xcrunFind(exec: String) throws -> AbsolutePath {
    let path = try Process.checkNonZeroExit(
      arguments: ["xcrun", "-sdk", "macosx", "--find", exec]).spm_chomp()
    return AbsolutePath(path)
  }
}
