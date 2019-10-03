import XCTest
import TSCBasic

import SwiftDriver

#if os(macOS)
private func bundleRoot() -> AbsolutePath {
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        return AbsolutePath(bundle.bundlePath).parentDirectory
    }
    fatalError()
}
#endif


final class IntegrationTests: IntegrationTestCase {
  func testSelfHosting() throws {
  #if os(macOS)
    try withTemporaryDirectory() { path in
      let binDir = bundleRoot()
      let driver = binDir.appending(component: "swift-driver")
      let compiler = path.appending(component: "swiftc")
      try createSymlink(compiler, pointingAt: driver, relative: false)

      let pkg = AbsolutePath(#file).parentDirectory.parentDirectory.parentDirectory

      var env = ProcessEnv.vars
      env["SWIFT_EXEC"] = compiler.pathString

      let buildPath = path.appending(component: "build")
      let result = try TSCBasic.Process.checkNonZeroExit(
        arguments: [
          "swift", "build", "--package-path", pkg.pathString,
          "--build-path", buildPath.pathString
        ],
        environment: env
      )

      XCTAssertTrue(localFileSystem.isExecutableFile(buildPath.appending(RelativePath("debug/swift-driver"))), result)
    }
  #endif
  }
}

/// A helper class for optionally running integration tests.
open class IntegrationTestCase: XCTestCase {
  override open class var defaultTestSuite: XCTestSuite {
    if ProcessEnv.vars.keys.contains("SWIFT_DRIVER_ENABLE_INTEGRATION_TESTS") {
      return super.defaultTestSuite
    }
    return XCTestSuite(name: String(describing: type(of: self)))
  }
}
