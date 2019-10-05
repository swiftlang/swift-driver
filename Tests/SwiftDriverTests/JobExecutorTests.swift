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
  var finished: [(Job, ProcessResult)] = []

  func jobFinished(job: Job, result: ProcessResult, pid: Int) {
    finished.append((job, result))
  }

  func jobStarted(job: Job, arguments: [String], pid: Int) {
    started.append(job)
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

      var resolver = try ArgsResolver()
      resolver.pathMapping = [
        .relative(RelativePath("foo.swift")): foo,
        .relative(RelativePath("main.swift")): main,
        .relative(RelativePath("main")): exec,
      ]

      let compileFoo = Job(
        kind: .compile,
        tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
        commandLine: [
          "-frontend",
          "-c",
          "-primary-file",
          .path(.relative(RelativePath("foo.swift"))),
          .path(.relative(RelativePath("main.swift"))),
          "-target", "x86_64-apple-darwin18.7.0",
          "-enable-objc-interop",
          "-sdk",
          .path(.absolute(try toolchain.sdk.get())),
          "-module-name", "main",
          "-o", .path(.temporary("foo.o")),
        ],
        inputs: [
          .init(file: .relative(RelativePath("foo.swift")), type: .swift),
          .init(file: .relative(RelativePath("main.swift")), type: .swift),
        ],
        outputs: [.init(file: .temporary("foo.o"), type: .object)]
      )

      let compileMain = Job(
        kind: .compile,
        tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
        commandLine: [
          "-frontend",
          "-c",
          .path(.relative(RelativePath("foo.swift"))),
          "-primary-file",
          .path(.relative(RelativePath("main.swift"))),
          "-target", "x86_64-apple-darwin18.7.0",
          "-enable-objc-interop",
          "-sdk",
          .path(.absolute(try toolchain.sdk.get())),
          "-module-name", "main",
          "-o", .path(.temporary("main.o")),
        ],
        inputs: [
          .init(file: .relative(RelativePath("foo.swift")), type: .swift),
          .init(file: .relative(RelativePath("main.swift")), type: .swift),
        ],
        outputs: [.init(file: .temporary("main.o"), type: .object)]
      )

      let link = Job(
        kind: .link,
        tool: .absolute(try toolchain.getToolPath(.dynamicLinker)),
        commandLine: [
          .path(.temporary("foo.o")),
          .path(.temporary("main.o")),
          .path(.absolute(try toolchain.clangRT.get())),
          "-syslibroot", .path(.absolute(try toolchain.sdk.get())),
          "-lobjc", "-lSystem", "-arch", "x86_64",
          "-force_load", .path(.absolute(try toolchain.compatibility50.get())),
          "-force_load", .path(.absolute(try toolchain.compatibilityDynamicReplacements.get())),
          "-L", .path(.absolute(try toolchain.resourcesDirectory.get())),
          "-L", .path(.absolute(try toolchain.sdkStdlib(sdk: toolchain.sdk.get()))),
          "-rpath", "/usr/lib/swift", "-macosx_version_min", "10.14.0", "-no_objc_category_merging", "-o",
          .path(.relative(RelativePath("main"))),
        ],
        inputs: [
          .init(file: .temporary("foo.o"), type: .object),
          .init(file: .temporary("main.o"), type: .object),
        ],
        outputs: [.init(file: .relative(RelativePath("main")), type: .image)]
      )

      let delegate = JobCollectingDelegate()
      let executor = JobExecutor(jobs: [compileFoo, compileMain, link], resolver: resolver, executorDelegate: delegate)
      try executor.build(.relative(RelativePath("main")))

      let output = try TSCBasic.Process.checkNonZeroExit(args: exec.pathString)
      XCTAssertEqual(output, "5\n")
      XCTAssertEqual(delegate.started.count, 3)

      let fooObject = try resolver.resolve(.path(.temporary("foo.o")))
      XCTAssertTrue(localFileSystem.exists(AbsolutePath(fooObject)), "expected foo.o to be present in the temporary directory")
      try resolver.removeTemporaryDirectory()
      XCTAssertFalse(localFileSystem.exists(AbsolutePath(fooObject)), "expected foo.o to be removed from the temporary directory")
    }
#endif
  }

  func testStubProcessProtocol() throws {
    struct StubProcess: ProcessProtocol {
      static func launchProcess(
        arguments: [String]
      ) throws -> ProcessProtocol {
        return StubProcess()
      }

      var processID: TSCBasic.Process.ProcessID { .init(-1) }

      func waitUntilExit() throws -> ProcessResult {
        return ProcessResult(
          arguments: [],
          exitStatus: .terminated(code: 0),
          output: Result.success(ByteString("test").contents),
          stderrOutput: Result.success([])
        )
      }
    }

    let job = Job(
      kind: .compile,
      tool: .absolute(AbsolutePath("/usr/bin/swift")),
      commandLine: [.flag("something")],
      inputs: [],
      outputs: [.init(file: .temporary("main"), type: .object)]
    )

    let delegate = JobCollectingDelegate()
    let executor = JobExecutor(
      jobs: [job], resolver: try ArgsResolver(),
      executorDelegate: delegate,
      processProtocol: StubProcess.self
    )
    try executor.build(.temporary("main"))

    XCTAssertEqual(try delegate.finished[0].1.utf8Output(), "test")
  }
}
