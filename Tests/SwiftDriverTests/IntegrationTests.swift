//===--------------- IntegrationTests.swift - Swift Integration Tests -----===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import XCTest
import TSCBasic


#if os(macOS)
private func bundleRoot() -> AbsolutePath {
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        return AbsolutePath(bundle.bundlePath).parentDirectory
    }
    fatalError()
}

private let packageDirectory = AbsolutePath(#file).parentDirectory.parentDirectory.parentDirectory

func makeDriverSymlinks(
  in tempDir: AbsolutePath,
  with swiftBuildDir: AbsolutePath? = nil
) throws -> (swift: AbsolutePath, swiftc: AbsolutePath) {
  let binDir = bundleRoot()
  let driver = binDir.appending(component: "swift-driver")
  
  let tempBinDir = tempDir.appending(components: "bin")
  try makeDirectories(tempBinDir)
  
  let swift = tempBinDir.appending(component: "swift")
  try createSymlink(swift, pointingAt: driver, relative: false)
  
  let swiftc = tempBinDir.appending(components: "swiftc")
  try createSymlink(swiftc, pointingAt: driver, relative: false)
  
  // If we've been given a build dir, link in its lib folder so we can find its
  // resource directory.
  if let swiftBuildDir = swiftBuildDir {
    let libDir = swiftBuildDir.appending(component: "lib")
    let tempLibDir = tempDir.appending(component: "lib" )
    try createSymlink(tempLibDir, pointingAt: libDir, relative: false)
  }

  return (swift: swift, swiftc: swiftc)
}

func printCommand(args: [String], extraEnv: [String: String]) {
  print("$", terminator: "")
  if !extraEnv.isEmpty {
    print(" env", terminator: "")
    for (key, value) in extraEnv {
      print(" \(key)=\(value.spm_shellEscaped())", terminator: "")
    }
  }
  for arg in args {
    print(" ", arg.spm_shellEscaped(), separator: "", terminator: "")
  }
  print()
}
#endif


final class IntegrationTests: IntegrationTestCase {
  // FIXME: This is failing on CI right now.
  func _testSelfHosting() throws {
  #if os(macOS)
    try withTemporaryDirectory() { path in
      let (swift: _, swiftc: compiler) = try makeDriverSymlinks(in: path)

      let buildPath = path.appending(component: "build")
      let args = [
        "swift", "build", "--package-path", packageDirectory.pathString,
        "--build-path", buildPath.pathString
      ]
      let extraEnv = [ "SWIFT_EXEC": compiler.pathString]

      printCommand(args: args, extraEnv: extraEnv)

      let result = try TSCBasic.Process.checkNonZeroExit(
        arguments: args,
        environment: ProcessEnv.vars.merging(extraEnv) { $1 }
      )

      XCTAssertTrue(localFileSystem.isExecutableFile(buildPath.appending(RelativePath("debug/swift-driver"))), result)
    }
  #endif
  }
  
  // These next few tests run lit test suites from a Swift working copy using
  // swift-driver in front of that working copy's Swift compiler. To enable
  // these tests, you must:
  //
  // 1. Set SWIFT_DRIVER_ENABLE_INTEGRATION_TESTS, as instructed elsewhere.
  //
  // 2. Clone Swift and its dependencies and run build-script with your favorite
  //    command-line options.
  //
  // 3. Set SWIFT_DRIVER_LIT_DIR to the path to the directory containing the
  //    lit.site.cfg file to use, e.g. "/path/to/swiftdev/build/
  //    Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/test-macosx-x86_64".
  //
  // 4. Open the console to see the results.
  //
  // If you don't set SWIFT_DRIVER_LIT_DIR, the tests will simply pass without
  // doing anything. If you do set it to something nonexistent or incorrect,
  // they will fail.
  
  func testLitDriverTests() throws {
    try runLitTests(suite: "test", "Driver")
  }
  
  func testLitDriverValidationTests() throws {
    try runLitTests(suite: "validation-test", "Driver")
  }
  
  func testLitInterpreterTests() throws {
    try runLitTests(suite: "test", "Interpreter")
  }
  
  func testLitStdlibTests() throws {
    try runLitTests(suite: "test", "stdlib")
  }

  func runLitTests(suite: String...) throws {
  #if os(macOS)
    try withTemporaryDirectory() { tempDir in
      guard
        let litConfigPathString = ProcessEnv.vars["SWIFT_DRIVER_LIT_DIR"]
      else {
        print("Skipping lit tests because SWIFT_DRIVER_LIT_DIR is not set")
        return
      }
      
      // SWIFT_DRIVER_LIT_DIR may be relative or absolute. If it's
      // relative, it's relative to the parent directory of the package. If
      // you've cloned this package into a Swift compiler working directory,
      // that means it'll be the directory with build/, llvm/, swift/, and
      // swift-driver/ in it.
      let litConfigDir = AbsolutePath(
        litConfigPathString,
        relativeTo: packageDirectory.parentDirectory
      )
      
      /// The site config file to use.
      let litConfigFile = litConfigDir.appending(component: "lit.site.cfg")

      /// The e.g. swift-macosx-x86_64 directory.
      let swiftBuildDir = litConfigDir.parentDirectory
      
      /// The path to the real frontend we should use.
      let frontendFile = swiftBuildDir.appending(components: "bin", "swift")
      
      /// The root directory, where build/, llvm/, and swift/ live.
      let swiftRootDir = swiftBuildDir.parentDirectory.parentDirectory.parentDirectory

      /// The path to lit.py.
      let litFile = swiftRootDir.appending(components: "llvm", "utils", "lit",
                                             "lit.py")

      /// The path to the test suite we want to run.
      let testDir = suite.reduce(swiftRootDir.appending(component: "swift")) {
        $0.appending(component: $1)
      }

      for path in [litFile, litConfigFile, frontendFile, testDir] {
        guard localFileSystem.exists(path) else {
          XCTFail("Lit tests enabled, but path doesn't exist: \(path)")
          return
        }
      }
      
      // Make dummy swift and swiftc files with an appropriately-positioned
      // resource directory.
      let (swift: swift, swiftc: swiftc) =
          try makeDriverSymlinks(in: tempDir, with: swiftBuildDir)

      let args = [
        litFile.pathString, "-svi", "--time-tests",
        "--param", "copy_env=SWIFT_DRIVER_SWIFT_EXEC",
        "--param", "swift_site_config=\(litConfigFile.pathString)",
        testDir.pathString
      ]
      
      let extraEnv = [
        "SWIFT": swift.pathString,
        "SWIFTC": swiftc.pathString,
        "SWIFT_DRIVER_SWIFT_EXEC": frontendFile.pathString
      ]
      
      printCommand(args: args, extraEnv: extraEnv)
      
      let process = TSCBasic.Process(
        arguments: args,
        environment: ProcessEnv.vars.merging(extraEnv) { $1 },
        outputRedirection: .none
      )
      try process.launch()
      let result = try process.waitUntilExit()
      XCTAssertEqual(result.exitStatus, .terminated(code: 0))
    }
  #endif
  }
}

/// A helper class for optionally running integration tests.
open class IntegrationTestCase: XCTestCase {
#if os(macOS)
  override open class var defaultTestSuite: XCTestSuite {
    if ProcessEnv.vars.keys.contains("SWIFT_DRIVER_ENABLE_INTEGRATION_TESTS") {
      return super.defaultTestSuite
    }
    return XCTestSuite(name: String(describing: type(of: self)))
  }
#endif
}
