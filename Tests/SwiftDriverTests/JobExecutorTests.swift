import XCTest
import TSCBasic

import SwiftDriver

extension Job.ArgTemplate: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .flag(value)
  }
}

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

      var resolver = ArgsResolver(toolchain: toolchain)
      resolver.pathMapping = [
        .path("foo.swift"): foo,
        .path("main.swift"): main,
        .path("foo.o"): fooObject,
        .path("main.o"): mainObject,
        .path("main"): exec,
      ]

      let compileFoo = Job(
        tool: .frontend,
        commandLine: [
          "-frontend",
          "-c",
          "-primary-file",
          .path(.path("foo.swift")),
          .path(.path("main.swift")),
          "-target", "x86_64-apple-darwin18.7.0",
          "-enable-objc-interop",
          "-sdk",
          .resource(.sdk),
          "-module-name", "main",
          "-o", .path(.path("foo.o")),
        ],
        inputs: [.path("foo.swift"), .path("main.swift")],
        outputs: [.path("foo.o")]
      )

      let compileMain = Job(
        tool: .frontend,
        commandLine: [
          "-frontend",
          "-c",
          .path(.path("foo.swift")),
          "-primary-file",
          .path(.path("main.swift")),
          "-target", "x86_64-apple-darwin18.7.0",
          "-enable-objc-interop",
          "-sdk",
          .resource(.sdk),
          "-module-name", "main",
          "-o", .path(.path("main.o")),
        ],
        inputs: [.path("foo.swift"), .path("main.swift")],
        outputs: [.path("main.o")]
      )

      let link = Job(
        tool: .ld,
        commandLine: [
          .path(.path("foo.o")),
          .path(.path("main.o")),
          .resource(.clangRT),
          "-syslibroot", .resource(.sdk),
          "-lobjc", "-lSystem", "-arch", "x86_64",
          "-force_load", .resource(.compatibility50),
          "-force_load", .resource(.compatibilityDynamicReplacements),
          "-L", .resource(.resourcesDir),
          "-L", .resource(.sdkStdlib),
          "-rpath", "/usr/lib/swift", "-macosx_version_min", "10.14.0", "-no_objc_category_merging", "-o",
          .path(.path("main")),
        ],
        inputs: [.path("foo.o"), .path("main.o")],
        outputs: [.path("main")]
      )

      let executor = JobExecutor(jobs: [compileFoo, compileMain, link], resolver: resolver)
      try executor.build(.path("main"))

      let output = try TSCBasic.Process.checkNonZeroExit(args: exec.pathString)
      XCTAssertEqual(output, "5\n")
    }
#endif
  }
}
