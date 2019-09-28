import XCTest
import TSCBasic

import SwiftDriver

final class JobExecutorTests: XCTestCase {
  func testDarwinBasic() throws {
#if os(macOS)
    let toolchain = DarwinToolchain()
    try withTemporaryDirectory { path in
      let foo = path.appending(component: "foo.swift")
      let main = path.appending(component: "main.swift")

      try localFileSystem.writeFileContents(foo) {
        $0 <<< "let foo = 5"
      }
      try localFileSystem.writeFileContents(main) {
        $0 <<< "print(foo)"
      }

      let fooObject = path.appending(component: "foo.o")
      let mainObject = path.appending(component: "main.o")
      let exec = path.appending(component: "main")

      let compileFoo = Job(
        tool: "swift",
        commandLine: [
          "-frontend",
          "-c",
          "-primary-file",
          foo.pathString,
          main.pathString,
          "-target", "x86_64-apple-darwin18.7.0",
          "-enable-objc-interop",
          "-sdk",
          try toolchain.sdk.path(),
          "-module-name", "main",
          "-o", fooObject.pathString
        ],
        inputs: [foo.pathString, main.pathString],
        outputs: [fooObject.pathString]
      )

      let compileMain = Job(
        tool: "swift",
        commandLine: [
          "-frontend",
          "-c",
          foo.pathString,
          "-primary-file",
          main.pathString,
          "-target", "x86_64-apple-darwin18.7.0",
          "-enable-objc-interop",
          "-sdk",
          try toolchain.sdk.path(),
          "-module-name", "main",
          "-o", mainObject.pathString
        ],
        inputs: [foo.pathString, main.pathString],
        outputs: [mainObject.pathString]
      )

      let link = Job(
        tool: "ld",
        commandLine: [
          fooObject.pathString,
          mainObject.pathString,
          try toolchain.clangRT.path(),
          "-syslibroot", try toolchain.sdk.path(),
          "-lobjc", "-lSystem", "-arch", "x86_64",
          "-force_load", try toolchain.compatibility50.path(),
          "-force_load", try toolchain.compatibilityDynamicReplacements.path(),
          "-L", try toolchain.resourcesDirectory.path(),
          "-L", try toolchain.sdkStdlib(sdk: toolchain.sdk.get()).pathString,
          "-rpath", "/usr/lib/swift", "-macosx_version_min", "10.14.0", "-no_objc_category_merging", "-o",
          exec.pathString,
        ],
        inputs: [
          fooObject.pathString,
          mainObject.pathString,
        ],
        outputs: [exec.pathString]
      )

      let executor = JobExecutor(jobs: [compileFoo, compileMain, link])
      try executor.build(exec.pathString)

      let output = try TSCBasic.Process.checkNonZeroExit(args: exec.pathString)
      XCTAssertEqual(output, "5\n")
    }
#endif
  }
}

extension DarwinToolchain {
  var compatibility50: Result<AbsolutePath, Error> {
    resourcesDirectory.map{ $0.appending(component: "libswiftCompatibility50.a") }
  }

  var compatibilityDynamicReplacements: Result<AbsolutePath, Error> {
    resourcesDirectory.map{ $0.appending(component: "libswiftCompatibilityDynamicReplacements.a") }
  }

  var clangRT: Result<AbsolutePath, Error> {
    resourcesDirectory.map{ $0.appending(RelativePath("../clang/lib/darwin/libclang_rt.osx.a")) }
  }
}

extension Result where Success == AbsolutePath {
  func path() throws -> String {
    return try get().pathString
  }
}
