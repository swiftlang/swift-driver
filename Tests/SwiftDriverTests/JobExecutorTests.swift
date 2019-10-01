import XCTest
import TSCBasic

import SwiftDriver

extension Job.ArgTemplate: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self = .flag(value)
  }
}

class JobCollectingDelegate: JobExecutorDelegate {
  var started: [Job] = []
  var finished: [Job] = []

  func jobStarted(job: Job) {
    started.append(job)
  }

  func jobHadOutput(job: Job, output: String) {

  }

  func jobFinished(job: Job, success: Bool) {
    finished.append(job)
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

      let exec = path.appending(component: "main")

      var resolver = try ArgsResolver(toolchain: toolchain)
      resolver.pathMapping = [
        .path(.relative(RelativePath("foo.swift"))): foo,
        .path(.relative(RelativePath("main.swift"))): main,
        .path(.relative(RelativePath("main"))): exec,
      ]

      let compileFoo = Job(
        tool: .frontend,
        commandLine: [
          "-frontend",
          "-c",
          "-primary-file",
          .path(.path(.relative(RelativePath("foo.swift")))),
          .path(.path(.relative(RelativePath("main.swift")))),
          "-target", "x86_64-apple-darwin18.7.0",
          "-enable-objc-interop",
          "-sdk",
          .resource(.sdk),
          "-module-name", "main",
          "-o", .path(.temporaryFile("foo.o")),
        ],
        inputs: [.path(.relative(RelativePath("foo.swift"))),
                 .path(.relative(RelativePath("main.swift")))],
        outputs: [.temporaryFile("foo.o")]
      )

      let compileMain = Job(
        tool: .frontend,
        commandLine: [
          "-frontend",
          "-c",
          .path(.path(.relative(RelativePath("foo.swift")))),
          "-primary-file",
          .path(.path(.relative(RelativePath("main.swift")))),
          "-target", "x86_64-apple-darwin18.7.0",
          "-enable-objc-interop",
          "-sdk",
          .resource(.sdk),
          "-module-name", "main",
          "-o", .path(.temporaryFile("main.o")),
        ],
        inputs: [.path(.relative(RelativePath("foo.swift"))), .path(.relative(RelativePath("main.swift")))],
        outputs: [.temporaryFile("main.o")]
      )

      let link = Job(
        tool: .ld,
        commandLine: [
          .path(.temporaryFile("foo.o")),
          .path(.temporaryFile("main.o")),
          .resource(.clangRT),
          "-syslibroot", .resource(.sdk),
          "-lobjc", "-lSystem", "-arch", "x86_64",
          "-force_load", .resource(.compatibility50),
          "-force_load", .resource(.compatibilityDynamicReplacements),
          "-L", .resource(.resourcesDir),
          "-L", .resource(.sdkStdlib),
          "-rpath", "/usr/lib/swift", "-macosx_version_min", "10.14.0", "-no_objc_category_merging", "-o",
          .path(.path(.relative(RelativePath("main")))),
        ],
        inputs: [.temporaryFile("foo.o"), .temporaryFile("main.o")],
        outputs: [.path(.relative(RelativePath("main")))]
      )

      let delegate = JobCollectingDelegate()
      let executor = JobExecutor(jobs: [compileFoo, compileMain, link], resolver: resolver, executorDelegate: delegate)
      try executor.build(.path(.relative(RelativePath("main"))))

      let output = try TSCBasic.Process.checkNonZeroExit(args: exec.pathString)
      XCTAssertEqual(output, "5\n")
      XCTAssertEqual(delegate.started.count, 3)

      let fooObject = try resolver.resolve(.path(.temporaryFile("foo.o")))
      XCTAssertTrue(localFileSystem.exists(AbsolutePath(fooObject)), "expected foo.o to be present in the temporary directory")
      try resolver.removeTemporaryDirectory()
      XCTAssertFalse(localFileSystem.exists(AbsolutePath(fooObject)), "expected foo.o to be removed from the temporary directory")
    }
#endif
  }
}
