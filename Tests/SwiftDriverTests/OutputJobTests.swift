//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@testable @_spi(Testing) import SwiftDriver
import SwiftDriverExecution
import SwiftOptions
import TSCBasic
import Testing
import TestUtilities

@Suite struct OutputJobTests {

  private var ld: AbsolutePath { get throws { try makeLdStub() } }

  @Test func recordedInputModificationDates() throws {
    guard let cwd = localFileSystem.currentWorkingDirectory else {
      fatalError()
    }

    try withTemporaryDirectory(dir: cwd, removeTreeOnDeinit: true) { path in
      let main = path.appending(component: "main.swift")
      let util = path.appending(component: "util.swift")
      let utilRelative = util.relative(to: cwd)
      try localFileSystem.writeFileContents(main, bytes: "print(hi)")
      try localFileSystem.writeFileContents(util, bytes: "let hi = \"hi\"")

      let mainMDate = try localFileSystem.lastModificationTime(for: .absolute(main))
      let utilMDate = try localFileSystem.lastModificationTime(for: .absolute(util))
      let driver = try TestDriver(args: [
        "swiftc", main.pathString, utilRelative.pathString,
      ])
      expectEqual(driver.recordedInputMetadata.mapValues{$0.mTime}, [
        .init(file: VirtualPath.absolute(main).intern(), type: .swift) : mainMDate,
        .init(file: VirtualPath.relative(utilRelative).intern(), type: .swift) : utilMDate,
      ])
    }
  }

  @Test func baseOutputPaths() async throws {
    // Test the combination of -c and -o includes the base output path.
    do {
      var driver = try TestDriver(args: ["swiftc", "-c", "foo.swift", "-o", "/some/output/path/bar.o"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(plannedJobs.count == 1)
      #expect(plannedJobs[0].kind == .compile)
      try expectJobInvocationMatches(plannedJobs[0], .path(VirtualPath(path: "/some/output/path/bar.o")))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-sil", "foo.swift", "-o", "/some/output/path/bar.sil"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      #expect(plannedJobs[0].kind == .compile)
      try expectJobInvocationMatches(plannedJobs[0], .path(VirtualPath(path: "/some/output/path/bar.sil")))
    }

    do {
      // If no output is specified, verify we print to stdout for textual formats.
      var driver = try TestDriver(args: ["swiftc", "-emit-assembly", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      #expect(plannedJobs.count == 1)
      #expect(plannedJobs[0].kind == .compile)
      expectJobInvocationMatches(plannedJobs[0], .path(.standardOutput))
    }
  }

  @Test func outputFileMapLoading() async throws {
    let objroot: AbsolutePath =
        try AbsolutePath(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build")

    let contents = ByteString("""
    {
      "": {
        "swift-dependencies": "\(objroot.appending(components: "main.swiftdeps").nativePathString(escaped: true))"
      },
      "/tmp/foo/Sources/foo/foo.swift": {
        "dependencies": "\(objroot.appending(components: "foo.d").nativePathString(escaped: true))",
        "object": "\(objroot.appending(components: "foo.swift.o").nativePathString(escaped: true))",
        "swiftmodule": "\(objroot.appending(components: "foo~partial.swiftmodule").nativePathString(escaped: true))",
        "swift-dependencies": "\(objroot.appending(components: "foo.swiftdeps").nativePathString(escaped: true))"
      }
    }
    """.utf8)

    try await withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try await assertNoDiagnostics { diags in
        try localFileSystem.writeFileContents(file, bytes: contents)
        let outputFileMap = try OutputFileMap.load(fileSystem: localFileSystem, file: .absolute(file), diagnosticEngine: diags)

        let object = try outputFileMap.getOutput(inputFile: VirtualPath.intern(path: "/tmp/foo/Sources/foo/foo.swift"), outputType: .object)
        #expect(VirtualPath.lookup(object).name == objroot.appending(components: "foo.swift.o").pathString)

        let mainDeps = try outputFileMap.getOutput(inputFile: VirtualPath.intern(path: ""), outputType: .swiftDeps)
        #expect(VirtualPath.lookup(mainDeps).name == objroot.appending(components: "main.swiftdeps").pathString)
      }
    }
  }

  @Test func findingObjectPathFromllvmBCPath() async throws {
    let objroot: AbsolutePath =
        try AbsolutePath(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build")

    let contents = ByteString(
      """
      {
        "": {
          "swift-dependencies": "\(objroot.appending(components: "main.swiftdeps").nativePathString(escaped: true))"
        },
        "/tmp/foo/Sources/foo/foo.swift": {
          "dependencies": "\(objroot.appending(components: "foo.d").nativePathString(escaped: true))",
          "object": "\(objroot.appending(components: "foo.swift.o").nativePathString(escaped: true))",
          "swiftmodule": "\(objroot.appending(components: "foo~partial.swiftmodule").nativePathString(escaped: true))",
          "swift-dependencies": "\(objroot.appending(components: "foo.swiftdeps").nativePathString(escaped: true))",
          "llvm-bc": "\(objroot.appending(components: "foo.swift.bc").nativePathString(escaped: true))"
        }
      }
      """.utf8
    )
    try await withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try await assertNoDiagnostics { diags in
        try localFileSystem.writeFileContents(file, bytes: contents)
        let outputFileMap = try OutputFileMap.load(fileSystem: localFileSystem, file: .absolute(file), diagnosticEngine: diags)

        let obj = try outputFileMap.getOutput(inputFile: VirtualPath.intern(path: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swift.bc"), outputType: .object)
        #expect(VirtualPath.lookup(obj).name == objroot.appending(components: "foo.swift.o").pathString)
      }
    }
  }

  @Test func outputFileMapLoadingDocAndSourceinfo() async throws {
    let objroot: AbsolutePath =
        try AbsolutePath(validating: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build")

    let contents = ByteString(
      """
      {
        "": {
          "swift-dependencies": "\(objroot.appending(components: "main.swiftdeps").nativePathString(escaped: true))"
        },
        "/tmp/foo/Sources/foo/foo.swift": {
          "dependencies": "\(objroot.appending(components: "foo.d").nativePathString(escaped: true))",
          "object": "\(objroot.appending(components: "foo.swift.o").nativePathString(escaped: true))",
          "swiftmodule": "\(objroot.appending(components: "foo~partial.swiftmodule").nativePathString(escaped: true))",
          "swift-dependencies": "\(objroot.appending(components: "foo.swiftdeps").nativePathString(escaped: true))"
        }
      }
      """.utf8
    )

    try await withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try await assertNoDiagnostics { diags in
        try localFileSystem.writeFileContents(file, bytes: contents)
        let outputFileMap = try OutputFileMap.load(fileSystem: localFileSystem, file: .absolute(file), diagnosticEngine: diags)

        let doc = try outputFileMap.getOutput(inputFile: VirtualPath.intern(path: "/tmp/foo/Sources/foo/foo.swift"), outputType: .swiftDocumentation)
        #expect(VirtualPath.lookup(doc).name == objroot.appending(components: "foo~partial.swiftdoc").pathString)

        let source = try outputFileMap.getOutput(inputFile: VirtualPath.intern(path: "/tmp/foo/Sources/foo/foo.swift"), outputType: .swiftSourceInfoFile)
        #expect(VirtualPath.lookup(source).name == objroot.appending(components: "foo~partial.swiftsourceinfo").pathString)
      }
    }
  }

  @Test func indexUnitOutputPath() async throws {
    let contents = ByteString(
      """
      {
        "/tmp/main.swift": {
          "object": "/tmp/build1/main.o",
          "index-unit-output-path": "/tmp/build2/main.o",
        },
        "/tmp/second.swift": {
          "object": "/tmp/build1/second.o",
          "index-unit-output-path": "/tmp/build2/second.o",
        }
      }
      """.utf8
    )

    func getFileListElements(for filelistOpt: String, job: Job) -> [VirtualPath] {
      let optIndex = job.commandLine.firstIndex(of: .flag(filelistOpt))!
      let value = job.commandLine[job.commandLine.index(after: optIndex)]
      guard case let .path(.fileList(_, valueFileList)) = value else {
        Issue.record("Argument wasn't a filelist")
        return []
      }
      guard case let .list(inputs) = valueFileList else {
        Issue.record("FileList wasn't List")
        return []
      }
      return inputs
    }

    try await withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try await assertNoDiagnostics { diags in
        try localFileSystem.writeFileContents(file, bytes: contents)

        // 1. Incremental mode (single primary file)
        // a) without filelists
        var driver = try TestDriver(args: [
          "swiftc", "-c",
          "-output-file-map", file.pathString,
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift"
        ])
        var jobs = try await driver.planBuild()

        try expectJobInvocationMatches(jobs[0], .flag("-o"), .path(.absolute(.init(validating: "/tmp/build1/second.o"))))
        try expectJobInvocationMatches(jobs[0], .flag("-index-unit-output-path"), .path(.absolute(.init(validating: "/tmp/build2/second.o"))))

        try expectJobInvocationMatches(jobs[1], .flag("-o"), .path(.absolute(.init(validating: "/tmp/build1/main.o"))))
        try expectJobInvocationMatches(jobs[1], .flag("-index-unit-output-path"), .path(.absolute(.init(validating: "/tmp/build2/main.o"))))

        // b) with filelists
        driver = try TestDriver(args: [
          "swiftc", "-c", "-driver-filelist-threshold=0",
          "-output-file-map", file.pathString,
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift"
        ])
        jobs = try await driver.planBuild()
        try expectEqual(getFileListElements(for: "-output-filelist", job: jobs[0]),
                       [.absolute(try .init(validating: "/tmp/build1/second.o"))])
        try expectEqual(getFileListElements(for: "-index-unit-output-path-filelist", job: jobs[0]),
                       [.absolute(try .init(validating: "/tmp/build2/second.o"))])
        try expectEqual(getFileListElements(for: "-output-filelist", job: jobs[1]),
                       [.absolute(try .init(validating: "/tmp/build1/main.o"))])
        try expectEqual(getFileListElements(for: "-index-unit-output-path-filelist", job: jobs[1]),
                       [.absolute(try .init(validating: "/tmp/build2/main.o"))])

        // 2. Batch mode (two primary files)
        // a) without filelists
        driver = try TestDriver(args: [
          "swiftc", "-c", "-enable-batch-mode", "-driver-batch-count", "1",
          "-output-file-map", file.pathString,
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift"
        ])
        jobs = try await driver.planBuild()

        try expectJobInvocationMatches(jobs[0], .flag("-o"), .path(.absolute(.init(validating: "/tmp/build1/second.o"))))
        try expectJobInvocationMatches(jobs[0], .flag("-index-unit-output-path"), .path(.absolute(.init(validating: "/tmp/build2/second.o"))))

        try expectJobInvocationMatches(jobs[0], .flag("-o"), .path(.absolute(.init(validating: "/tmp/build1/main.o"))))
        try expectJobInvocationMatches(jobs[0], .flag("-index-unit-output-path"), .path(.absolute(.init(validating: "/tmp/build2/main.o"))))

        // b) with filelists
        driver = try TestDriver(args: [
          "swiftc", "-c", "-driver-filelist-threshold=0",
          "-enable-batch-mode", "-driver-batch-count", "1",
          "-output-file-map", file.pathString,
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift"
        ])
        jobs = try await driver.planBuild()
        try expectEqual(getFileListElements(for: "-output-filelist", job: jobs[0]),
                       [.absolute(try .init(validating: "/tmp/build1/second.o")), .absolute(try .init(validating: "/tmp/build1/main.o"))])
        try expectEqual(getFileListElements(for: "-index-unit-output-path-filelist", job: jobs[0]),
                       [.absolute(try .init(validating: "/tmp/build2/second.o")), .absolute(try .init(validating: "/tmp/build2/main.o"))])

        // 3. Multi-threaded WMO
        // a) without filelists
        driver = try TestDriver(args: [
          "swiftc", "-c", "-whole-module-optimization", "-num-threads", "2",
          "-output-file-map", file.pathString,
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift"
        ])
        jobs = try await driver.planBuild()

        try expectJobInvocationMatches(jobs[0], .flag("-o"), .path(.absolute(.init(validating: "/tmp/build1/second.o"))))
        try expectJobInvocationMatches(jobs[0], .flag("-index-unit-output-path"), .path(.absolute(.init(validating: "/tmp/build2/second.o"))))

        try expectJobInvocationMatches(jobs[0], .flag("-o"), .path(.absolute(.init(validating: "/tmp/build1/main.o"))))
        try expectJobInvocationMatches(jobs[0], .flag("-index-unit-output-path"), .path(.absolute(.init(validating: "/tmp/build2/main.o"))))

        // b) with filelists
        driver = try TestDriver(args: [
          "swiftc", "-c", "-driver-filelist-threshold=0",
          "-whole-module-optimization", "-num-threads", "2",
          "-output-file-map", file.pathString,
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift"
        ])
        jobs = try await driver.planBuild()
        try expectEqual(getFileListElements(for: "-output-filelist", job: jobs[0]),
                       [.absolute(try .init(validating: "/tmp/build1/second.o")), .absolute(try .init(validating: "/tmp/build1/main.o"))])
        try expectEqual(getFileListElements(for: "-index-unit-output-path-filelist", job: jobs[0]),
                       [.absolute(try .init(validating: "/tmp/build2/second.o")), .absolute(try .init(validating: "/tmp/build2/main.o"))])

        // 4. Index-file (single primary)
        driver = try TestDriver(args: [
          "swiftc", "-c", "-enable-batch-mode", "-driver-batch-count", "1",
          "-module-name", "test", "/tmp/second.swift", "/tmp/main.swift",
          "-index-file", "-index-file-path", "/tmp/second.swift",
          "-disable-batch-mode", "-o", "/tmp/build1/second.o",
          "-index-unit-output-path", "/tmp/build2/second.o"
        ])
        jobs = try await driver.planBuild()

        try expectJobInvocationMatches(jobs[0], .flag("-o"), .path(.absolute(.init(validating: "/tmp/build1/second.o"))))
        try expectJobInvocationMatches(jobs[0], .flag("-index-unit-output-path"), .path(.absolute(.init(validating: "/tmp/build2/second.o"))))
      }
    }
  }

  @Test func outputFileMapStoring() throws {
    // Create sample OutputFileMap:

    // Rather than writing VirtualPath(path:...) over and over again, make strings, then fix it
    let stringyEntries: [String: [FileType: String]] = [
      "": [.swiftDeps: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/main.swiftdeps"],
      "foo.swift" : [
        .dependencies: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.d",
        .object: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swift.o",
        .swiftModule: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo~partial.swiftmodule",
        .swiftDeps: "/tmp/foo/.build/x86_64-apple-macosx/debug/foo.build/foo.swiftdeps"
        ]
    ]
    let pathyEntries = try Dictionary(uniqueKeysWithValues:
      stringyEntries.map { try
        (
          VirtualPath.intern(path: $0.key),
          Dictionary(uniqueKeysWithValues: $0.value.map { try ($0.key, VirtualPath.intern(path: $0.value))})
        )})
    let sampleOutputFileMap = OutputFileMap(entries: pathyEntries)

    try withTemporaryDirectory { dir in
      let file = dir.appending(component: "file")
      try sampleOutputFileMap.store(fileSystem: localFileSystem, file: file)
      let contentsForDebugging = try localFileSystem.readFileContents(file).cString
      _ = contentsForDebugging
      let recoveredOutputFileMap = try OutputFileMap.load(fileSystem: localFileSystem, file: .absolute(file), diagnosticEngine: DiagnosticsEngine())
      #expect(sampleOutputFileMap == recoveredOutputFileMap)
    }
  }

  @Test func outputFileMapResolving() throws {
    // Create sample OutputFileMap:

    let stringyEntries: [String: [FileType: String]] = [
      "": [.swiftDeps: "foo.build/main.swiftdeps"],
      "foo.swift" : [
        .dependencies: "foo.build/foo.d",
        .object: "foo.build/foo.swift.o",
        .swiftModule: "foo.build/foo~partial.swiftmodule",
        .swiftDeps: "foo.build/foo.swiftdeps"
      ]
    ]

    let root = localFileSystem.currentWorkingDirectory!.appending(components: "foo_root")

    let resolvedStringyEntries: [String: [FileType: String]] = [
      "": [.swiftDeps: root.appending(components: "foo.build", "main.swiftdeps").pathString],
      root.appending(component: "foo.swift").pathString : [
        .dependencies: root.appending(components: "foo.build", "foo.d").pathString,
        .object: root.appending(components: "foo.build", "foo.swift.o").pathString,
        .swiftModule: root.appending(components: "foo.build", "foo~partial.swiftmodule").pathString,
        .swiftDeps: root.appending(components: "foo.build", "foo.swiftdeps").pathString
      ]
    ]

    func outputFileMapFromStringyEntries(
      _ entries: [String: [FileType: String]]
    ) throws -> OutputFileMap {
      .init(entries: Dictionary(uniqueKeysWithValues: try entries.map { try (
        VirtualPath.intern(path: $0.key),
        $0.value.mapValues(VirtualPath.intern(path:))
      )}))
    }

    let sampleOutputFileMap =
      try outputFileMapFromStringyEntries(stringyEntries)
    let resolvedOutputFileMap = sampleOutputFileMap
      .resolveRelativePaths(relativeTo: root)
    let expectedOutputFileMap =
      try outputFileMapFromStringyEntries(resolvedStringyEntries)
    #expect(expectedOutputFileMap == resolvedOutputFileMap)
  }

  @Test func outputFileMapRelativePathArg() throws {
    guard let cwd = localFileSystem.currentWorkingDirectory else {
      fatalError()
    }

    try withTemporaryDirectory(dir: cwd, removeTreeOnDeinit: true) { path in
      let outputFileMap = path.appending(component: "outputFileMap.json")
      try localFileSystem.writeFileContents(outputFileMap, bytes:
        """
        {
          "": {
            "swift-dependencies": "build/main.swiftdeps"
          },
          "main.swift": {
            "object": "build/main.o",
            "dependencies": "build/main.o.d"
          },
          "util.swift": {
            "object": "build/util.o",
            "dependencies": "build/util.o.d"
          }
        }
        """
      )
      let outputFileMapRelative = outputFileMap.relative(to: cwd).pathString
      // FIXME: Needs a better way to check that outputFileMap correctly loaded
      #expect(throws: Never.self) { try TestDriver(args: [
        "swiftc",
        "-output-file-map", outputFileMapRelative,
        "main.swift", "util.swift",
      ]) }
    }
  }

  @Test func referenceDependencies() async throws {
    var driver = try TestDriver(args: ["swiftc", "foo.swift", "-incremental"])
    let plannedJobs = try await driver.planBuild()

    #expect(plannedJobs[0].kind == .compile)
    expectJobInvocationMatches(plannedJobs[0], .flag("-emit-reference-dependencies-path"))
  }

  @Test func responseFileExpansion() throws {
    try withTemporaryDirectory { path in
      let diags = DiagnosticsEngine()
      let fooPath = path.appending(component: "foo.rsp")
      let barPath = path.appending(component: "bar.rsp")
#if os(Windows)
      try localFileSystem.writeFileContents(fooPath, bytes:
        .init("hello\nbye\n\"bye to you\"\n@\(barPath.nativePathString(escaped: true))".utf8)
      )
#else
      try localFileSystem.writeFileContents(fooPath, bytes:
        .init("hello\nbye\nbye\\ to\\ you\n@\(barPath.nativePathString(escaped: true))".utf8)
      )
#endif
      try localFileSystem.writeFileContents(barPath, bytes:
        .init("from\nbar\n@\(fooPath.nativePathString(escaped: true))".utf8)
      )
      let args = try Driver.expandResponseFiles(["swift", "compiler", "-Xlinker", "@loader_path", "@" + fooPath.pathString, "something"], fileSystem: localFileSystem, diagnosticsEngine: diags)
      #expect(args == ["swift", "compiler", "-Xlinker", "@loader_path", "hello", "bye", "bye to you", "from", "bar", "something"])
      #expect(diags.diagnostics.count == 1)
      #expect(diags.diagnostics.first?.description.contains("is recursively expanded") ?? false)
    }
  }

  @Test func responseFileExpansionRelativePathsInCWD() throws {
    try withTemporaryDirectory { path in
      let fs = TestLocalFileSystem(cwd: path)

      let diags = DiagnosticsEngine()
      let fooPath = path.appending(component: "foo.rsp")
      let barPath = path.appending(component: "bar.rsp")
#if os(Windows)
      try localFileSystem.writeFileContents(fooPath, bytes: "hello\nbye\n\"bye to you\"\n@bar.rsp")
#else
      try localFileSystem.writeFileContents(fooPath, bytes: "hello\nbye\nbye\\ to\\ you\n@bar.rsp")
#endif
      try localFileSystem.writeFileContents(barPath, bytes: "from\nbar\n@foo.rsp")

      let args = try Driver.expandResponseFiles(["swift", "compiler", "-Xlinker", "@loader_path", "@foo.rsp", "something"], fileSystem: fs, diagnosticsEngine: diags)
      #expect(args == ["swift", "compiler", "-Xlinker", "@loader_path", "hello", "bye", "bye to you", "from", "bar", "something"])
      #expect(diags.diagnostics.count == 1)
      #expect(diags.diagnostics.first!.description.contains("is recursively expanded"))
    }
  }

  /// Tests that relative paths in response files are resolved based on the CWD, not the response file's location.
  @Test func responseFileExpansionRelativePathsNotInCWD() throws {
    try withTemporaryDirectory { path in
      let fs = TestLocalFileSystem(cwd: path)

      try localFileSystem.createDirectory(path.appending(component: "subdir"))

      let diags = DiagnosticsEngine()
      let fooPath = path.appending(components: "subdir", "foo.rsp")
      let barPath = path.appending(components: "subdir", "bar.rsp")
#if os(Windows)
      try localFileSystem.writeFileContents(fooPath, bytes: "hello\nbye\n\"bye to you\"\n@subdir/bar.rsp")
#else
      try localFileSystem.writeFileContents(fooPath, bytes: "hello\nbye\nbye\\ to\\ you\n@subdir/bar.rsp")
#endif
      try localFileSystem.writeFileContents(barPath, bytes: "from\nbar\n@subdir/foo.rsp")

      let args = try Driver.expandResponseFiles(["swift", "compiler", "-Xlinker", "@loader_path", "@subdir/foo.rsp", "something"], fileSystem: fs, diagnosticsEngine: diags)
      #expect(args == ["swift", "compiler", "-Xlinker", "@loader_path", "hello", "bye", "bye to you", "from", "bar", "something"])
      #expect(diags.diagnostics.count == 1)
      #expect(diags.diagnostics.first!.description.contains("is recursively expanded"))
    }
  }

  /// Tests how response files tokens such as spaces, comments, escaping characters and quotes, get parsed and expanded.
  @Test func responseFileTokenization() throws {
    try withTemporaryDirectory { path  in
      let diags = DiagnosticsEngine()
      let fooPath = path.appending(component: "foo.rsp")
      let barPath = path.appending(component: "bar.rsp")
      let escapingPath = path.appending(component: "escaping.rsp")

#if os(Windows)
      try localFileSystem.writeFileContents(fooPath, bytes:
        .init(("""
        a\\b c\\\\d e\\\\\"f g\" h\\\"i j\\\\\\\"k \"lmn\" o pqr \"st \\\"u\" \\v"
        @\(barPath.nativePathString(escaped: true))
        """).utf8)
      )
      try localFileSystem.writeFileContents(barPath, bytes:
       .init((#"""
        -Xswiftc -use-ld=lld
        -Xcc -IS:\Library\sqlite-3.36.0\usr\include
        -Xlinker -LS:\Library\sqlite-3.36.0\usr\lib
        """#).utf8)
      )
      let args = try Driver.expandResponseFiles(["@\(fooPath.pathString)"], fileSystem: localFileSystem, diagnosticsEngine: diags)
      #expect(args == ["a\\b", "c\\\\d", "e\\f g", "h\"i", "j\\\"k", "lmn", "o", "pqr", "st \"u", "\\v", "-Xswiftc", "-use-ld=lld", "-Xcc", "-IS:\\Library\\sqlite-3.36.0\\usr\\include", "-Xlinker", "-LS:\\Library\\sqlite-3.36.0\\usr\\lib"])
#else
      try localFileSystem.writeFileContents(fooPath, bytes:
        .init((#"""
          Command1 --kkc
          //This is a comment
          // this is another comment
          but this is \\\\\a command
          @\#(barPath.nativePathString(escaped: true))
          @NotAFile
          -flag="quoted string with a \"quote\" inside" -another-flag
          """#
          + "\nthis  line\thas        lots \t  of    whitespace").utf8
        )
      )

      try localFileSystem.writeFileContents(barPath, bytes:
        #"""
        swift
        "rocks!"
        compiler
        -Xlinker

        @loader_path
        mkdir "Quoted Dir"
        cd Unquoted\ Dir
        // Bye!
        """#
      )

      try localFileSystem.writeFileContents(escapingPath, bytes:
        "swift\n--driver-mode=swiftc\n-v\r\n//comment\n\"the end\""
      )
      let args = try Driver.expandResponseFiles(["@" + fooPath.pathString], fileSystem: localFileSystem, diagnosticsEngine: diags)
      #expect(args == ["Command1", "--kkc", "but", "this", "is", #"\\a"#, "command", #"swift"#, "rocks!" ,"compiler", "-Xlinker", "@loader_path", "mkdir", "Quoted Dir", "cd", "Unquoted Dir", "@NotAFile", #"-flag=quoted string with a "quote" inside"#, "-another-flag", "this", "line", "has", "lots", "of", "whitespace"])
      let escapingArgs = try Driver.expandResponseFiles(["@" + escapingPath.pathString], fileSystem: localFileSystem, diagnosticsEngine: diags)
      #expect(escapingArgs == ["swift", "--driver-mode=swiftc", "-v","the end"])
#endif
    }
  }

  @Test func usingResponseFiles() async throws {
    let manyArgs = (1...200000).map { "-DTEST_\($0)" }
    // Needs response file
    do {
      let source = try AbsolutePath(validating: "/foo.swift")
      var driver = try TestDriver(args: ["swift"] + manyArgs + [source.nativePathString(escaped: false)])
      let jobs = try await driver.planBuild()
      #expect(jobs.count == 1)
      #expect(jobs[0].kind == .interpret)
      let interpretJob = jobs[0]
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let resolvedArgs: [String] = try resolver.resolveArgumentList(for: interpretJob)
      #expect(resolvedArgs.count == 3)
      #expect(resolvedArgs[1] == "-frontend")
      #expect(resolvedArgs[2].first == "@")
      let responseFilePath = try AbsolutePath(validating: String(resolvedArgs[2].dropFirst()))
      let contents = try localFileSystem.readFileContents(responseFilePath).description
      #expect(contents.hasPrefix("-interpret\n\(source.nativePathString(escaped: false))"))
      #expect(contents.contains("-D\nTEST_20000"))
      #expect(contents.contains("-D\nTEST_1"))
    }

    // Needs response file + disable override
    do {
      var driver = try TestDriver(args: ["swift"] + manyArgs + ["foo.swift"])
      let jobs = try await driver.planBuild()
      #expect(jobs.count == 1)
      #expect(jobs[0].kind == .interpret)
      let interpretJob = jobs[0]
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let resolvedArgs: [String] = try resolver.resolveArgumentList(for: interpretJob, useResponseFiles: .disabled)
      #expect(!resolvedArgs.contains { $0.hasPrefix("@") })
    }

    // Forced response file
    do {
      let source = try AbsolutePath(validating: "/foo.swift")
      var driver = try TestDriver(args: ["swift"] + [source.nativePathString(escaped: false)])
      let jobs = try await driver.planBuild()
      #expect(jobs.count == 1)
      #expect(jobs[0].kind == .interpret)
      let interpretJob = jobs[0]
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let resolvedArgs: [String] = try resolver.resolveArgumentList(for: interpretJob, useResponseFiles: .forced)
      #expect(resolvedArgs.count == 3)
      #expect(resolvedArgs[1] == "-frontend")
      #expect(resolvedArgs[2].first == "@")
      let responseFilePath = try AbsolutePath(validating: String(resolvedArgs[2].dropFirst()))
      let contents = try localFileSystem.readFileContents(responseFilePath).description
      #expect(contents.hasPrefix("-interpret\n\(source.nativePathString(escaped: false))"))
    }

    // Forced response file in a non-existing temporary directory
    do {
      try await withTemporaryDirectory { tempPath in
        let resolverTempDirPath = tempPath.appending(components: "resolverStuff")
        let source = try AbsolutePath(validating: "/foo.swift")
        var driver = try TestDriver(args: ["swift"] + [source.nativePathString(escaped: false)])
        let jobs = try await driver.planBuild()
        #expect(jobs.count == 1)
        #expect(jobs[0].kind == .interpret)
        let interpretJob = jobs[0]
        let resolver = try ArgsResolver(fileSystem: localFileSystem,
                                        temporaryDirectory: .absolute(resolverTempDirPath))
        let resolvedArgs: [String] = try resolver.resolveArgumentList(for: interpretJob, useResponseFiles: .forced)
        #expect(resolvedArgs.count == 3)
        #expect(resolvedArgs[1] == "-frontend")
        #expect(resolvedArgs[2].first == "@")
        let responseFilePath = try AbsolutePath(validating: String(resolvedArgs[2].dropFirst()))
        expectEqual(responseFilePath.parentDirectory.basename, "resolverStuff")
        let contents = try localFileSystem.readFileContents(responseFilePath).description
        #expect(contents.hasPrefix("-interpret\n\(source.nativePathString(escaped: false))"))
      }
    }

    // Response file query with full command-line API
    do {
      let source = try AbsolutePath(validating: "/foo.swift")
      var driver = try TestDriver(args: ["swift"] + [source.nativePathString(escaped: false)])
      let jobs = try await driver.planBuild()
      #expect(jobs.count == 1)
      #expect(jobs[0].kind == .interpret)
      let interpretJob = jobs[0]
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let resolved: ResolvedCommandLine = try resolver.resolveArgumentList(for: interpretJob, useResponseFiles: .forced)
      guard case .usingResponseFile(resolved: let resolvedArgs, responseFileContents: let contents) = resolved else {
          Issue.record("Argument wasn't a response file")
        return
      }
      #expect(resolvedArgs.count == 3)
      #expect(resolvedArgs[1] == "-frontend")
      #expect(resolvedArgs[2].first == "@")

      #expect(contents.contains(subsequence: ["-frontend", "-interpret"]))
      #expect(contents.contains(subsequence: ["-module-name", "foo"]))
    }

    // No response file
    do {
      var driver = try TestDriver(args: ["swift"] + ["foo.swift"])
      let jobs = try await driver.planBuild()
      #expect(jobs.count == 1)
      #expect(jobs[0].kind == .interpret)
      let interpretJob = jobs[0]
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      let resolvedArgs: [String] = try resolver.resolveArgumentList(for: interpretJob)
      #expect(!resolvedArgs.contains { $0.hasPrefix("@") })
    }
  }

  @Test func specificJobsResponseFiles() async throws {
    // The jobs below often take large command lines (e.g., when passing a large number of Clang
    // modules to Swift). Ensure that they don't regress in their ability to pass response files
    // from the driver to the frontend.
    let manyArgs = (1...200000).map { "-DTEST_\($0)" }

    // Compile + separate emit module job
    do {
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var driver = try TestDriver(
        args: ["swiftc", "-emit-module"] + manyArgs
          + ["-module-name", "foo", "foo.swift", "bar.swift"])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      expectEqual(jobs.count, 3)
      expectEqual(Set(jobs.map { $0.kind }), Set([.emitModule, .compile]))

      let emitModuleJob = try jobs.findJob(.emitModule)
      let emitModuleResolvedArgs: [String] =
        try resolver.resolveArgumentList(for: emitModuleJob)
      expectEqual(emitModuleResolvedArgs.count, 3)
      expectEqual(emitModuleResolvedArgs[2].first, "@")

      let compileJobs = jobs.filter { $0.kind == .compile }
      expectEqual(compileJobs.count, 2)
      for compileJob in compileJobs {
        let compileResolvedArgs: [String] =
          try resolver.resolveArgumentList(for: compileJob)
        expectEqual(compileResolvedArgs.count, 3)
        expectEqual(compileResolvedArgs[2].first, "@")
      }
    }

    // Generate PCM (precompiled Clang module) job
    do {
      let resolver = try ArgsResolver(fileSystem: localFileSystem)
      var driver = try TestDriver(
        args: ["swiftc", "-emit-pcm"] + manyArgs + ["-module-name", "foo", "foo.modulemap"])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(jobs.count == 1)
      #expect(jobs[0].kind == .generatePCM)

      let generatePCMJob = jobs[0]
      let generatePCMResolvedArgs: [String] =
        try resolver.resolveArgumentList(for: generatePCMJob)
      expectEqual(generatePCMResolvedArgs.count, 3)
      expectEqual(generatePCMResolvedArgs[2].first, "@")
    }
  }

  @Test func emitSymbolGraphPrettyPrint() async throws {
    do {
      let root = localFileSystem.currentWorkingDirectory!.appending(components: "foo", "bar")

      var driver = try TestDriver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-emit-symbol-graph", "-emit-symbol-graph-dir", "/foo/bar/", "-symbol-graph-pretty-print", "-emit-library"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

      // We don't know the output file of the symbol graph, just make sure the flag is passed along.
      expectJobInvocationMatches(plannedJobs[0], .flag("-emit-symbol-graph"))
      expectJobInvocationMatches(plannedJobs[0], .flag("-symbol-graph-pretty-print"))
    }
  }

  @Test func emitSymbolGraphSkipSynthesizedMembers() async throws {
    do {
      let root = localFileSystem.currentWorkingDirectory!.appending(components: "foo", "bar")

      var driver = try TestDriver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-emit-symbol-graph", "-emit-symbol-graph-dir", "/foo/bar/", "-symbol-graph-skip-synthesized-members", "-emit-library"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

      // We don't know the output file of the symbol graph, just make sure the flag is passed along.
      expectJobInvocationMatches(plannedJobs[0], .flag("-emit-symbol-graph"))
      expectJobInvocationMatches(plannedJobs[0], .flag("-symbol-graph-skip-synthesized-members"))
    }
  }

  @Test func emitSymbolGraphSkipInheritedDocs() async throws {
    do {
      let root = localFileSystem.currentWorkingDirectory!.appending(components: "foo", "bar")

      var driver = try TestDriver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-emit-symbol-graph", "-emit-symbol-graph-dir", "/foo/bar/", "-symbol-graph-skip-inherited-docs", "-emit-library"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

      // We don't know the output file of the symbol graph, just make sure the flag is passed along.
      expectJobInvocationMatches(plannedJobs[0], .flag("-emit-symbol-graph"))
      expectJobInvocationMatches(plannedJobs[0], .flag("-symbol-graph-skip-inherited-docs"))
    }
  }

  @Test func emitSymbolGraphShortenModuleNames() async throws {
    do {
      let root = localFileSystem.currentWorkingDirectory!.appending(components: "foo", "bar")

      var driver = try TestDriver(args: ["swiftc", "foo.swift", "bar.swift", "-module-name", "Test", "-emit-module-path", rebase("Test.swiftmodule", at: root), "-emit-symbol-graph", "-emit-symbol-graph-dir", "/foo/bar/", "-symbol-graph-shorten-output-names"])
      let plannedJobs = try await driver.planBuild().removingAutolinkExtractJobs()

      expectJobInvocationMatches(plannedJobs[0], .flag("-symbol-graph-shorten-output-names"))
    }
  }

  @Test func sourceInfoFileEmitOption() async throws {
    // implicit
    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-module", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      let emitModuleJob = plannedJobs[0]
      expectJobInvocationMatches(emitModuleJob, .flag("-emit-module-source-info-path"))
      expectEqual(emitModuleJob.outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
      #expect(try emitModuleJob.outputs[0].file == toPath("foo.swiftmodule"))
      #expect(try emitModuleJob.outputs[1].file == toPath("foo.swiftdoc"))
      #expect(try emitModuleJob.outputs[2].file == toPath("foo.swiftsourceinfo"))
      if driver.targetTriple.isDarwin {
          #expect(try emitModuleJob.outputs[3].file == toPath("foo.abi.json"))
      }
    }
    // implicit with Project/ Directory
    do {
      try await withTemporaryDirectory { path in
        let projectDirPath = path.appending(component: "Project")
        try localFileSystem.createDirectory(projectDirPath)
        var driver = try TestDriver(args: ["swiftc", "-emit-module",
                                       path.appending(component: "foo.swift").description,
                                       "-o", path.appending(component: "foo.swiftmodule").description])
        let plannedJobs = try await driver.planBuild()
        let emitModuleJob = plannedJobs[0]
        expectJobInvocationMatches(emitModuleJob, .flag("-emit-module-source-info-path"))
        expectEqual(emitModuleJob.outputs.count, driver.targetTriple.isDarwin ? 4 : 3)
        #expect(emitModuleJob.outputs[0].file == .absolute(path.appending(component: "foo.swiftmodule")))
        #expect(emitModuleJob.outputs[1].file == .absolute(path.appending(component: "foo.swiftdoc")))
        #expect(emitModuleJob.outputs[2].file == .absolute(projectDirPath.appending(component: "foo.swiftsourceinfo")))
        if driver.targetTriple.isDarwin {
          #expect(emitModuleJob.outputs[3].file == .absolute(path.appending(component: "foo.abi.json")))
        }
      }
    }
    // avoid implicit swiftsourceinfo
    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-module", "-avoid-emit-module-source-info", "foo.swift"])
      let plannedJobs = try await driver.planBuild()
      let emitModuleJob = plannedJobs[0]
      #expect(!emitModuleJob.commandLine.contains(.flag("-emit-module-source-info-path")))
      expectEqual(emitModuleJob.outputs.count, driver.targetTriple.isDarwin ? 3 : 2)
      #expect(try emitModuleJob.outputs[0].file == toPath("foo.swiftmodule"))
      #expect(try emitModuleJob.outputs[1].file == toPath("foo.swiftdoc"))
      if driver.targetTriple.isDarwin {
          #expect(try emitModuleJob.outputs[2].file == toPath("foo.abi.json"))
      }
    }
  }

  @Test func filelist() async throws {
    var envVars = ProcessEnv.block
    envVars["SWIFT_DRIVER_LD_EXEC"] = try ld.nativePathString(escaped: false)

    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-module", "./a.swift", "./b.swift", "./c.swift", "-module-name", "main", "-target", "x86_64-apple-macosx10.9", "-driver-filelist-threshold=0", "-no-emit-module-separately"],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()

      let jobA = plannedJobs[0]
      let mapA = try jobA.commandLine.supplementaryOutputFilemap
      let filesA = try #require(mapA.entries[try toPath("./a.swift").intern()])
      #expect(filesA.keys.contains(.swiftModule))
      #expect(filesA.keys.contains(.swiftDocumentation))
      #expect(filesA.keys.contains(.swiftSourceInfoFile))

      let jobB = plannedJobs[1]
      let mapB = try jobB.commandLine.supplementaryOutputFilemap
      let filesB = try #require(mapB.entries[try toPath("./b.swift").intern()])
      #expect(filesB.keys.contains(.swiftModule))
      #expect(filesB.keys.contains(.swiftDocumentation))
      #expect(filesB.keys.contains(.swiftSourceInfoFile))

      let jobC = plannedJobs[2]
      let mapC = try jobC.commandLine.supplementaryOutputFilemap
      let filesC = try #require(mapC.entries[try toPath("./c.swift").intern()])
      #expect(filesC.keys.contains(.swiftModule))
      #expect(filesC.keys.contains(.swiftDocumentation))
      #expect(filesC.keys.contains(.swiftSourceInfoFile))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-c", "./a.swift", "./b.swift", "./c.swift", "-module-name", "main", "-target", "x86_64-apple-macosx10.9", "-driver-filelist-threshold=0", "-whole-module-optimization"],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()
      let job = plannedJobs[0]
      let inputsFlag = job.commandLine.firstIndex(of: .flag("-filelist"))!
      let inputFileListArgument = job.commandLine[job.commandLine.index(after: inputsFlag)]
      guard case let .path(.fileList(_, inputFileList)) = inputFileListArgument else {
        Issue.record("Argument wasn't a filelist")
        return
      }
      guard case let .list(inputs) = inputFileList else {
        Issue.record("FileList wasn't List")
        return
      }
      try expectEqual(inputs, [try toPath("./a.swift"), try toPath("./b.swift"), try toPath("./c.swift")])

      let outputsFlag = job.commandLine.firstIndex(of: .flag("-output-filelist"))!
      let outputFileListArgument = job.commandLine[job.commandLine.index(after: outputsFlag)]
      guard case let .path(.fileList(_, outputFileList)) = outputFileListArgument else {
        Issue.record("Argument wasn't a filelist")
        return
      }
      guard case let .list(outputs) = outputFileList else {
        Issue.record("FileList wasn't List")
        return
      }
      try expectEqual(outputs, [try toPath("main.o")])
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-c", "./a.swift", "./b.swift", "./c.swift", "-module-name", "main", "-target", "x86_64-apple-macosx10.9", "-driver-filelist-threshold=0", "-whole-module-optimization", "-num-threads", "1"],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()
      let job = plannedJobs[0]
      let outputsFlag = job.commandLine.firstIndex(of: .flag("-output-filelist"))!
      let outputFileListArgument = job.commandLine[job.commandLine.index(after: outputsFlag)]
      guard case let .path(.fileList(_, outputFileList)) = outputFileListArgument else {
        Issue.record("Argument wasn't a filelist")
        return
      }
      guard case let .list(outputs) = outputFileList else {
        Issue.record("FileList wasn't List")
        return
      }
      try expectEqual(outputs, [try toPath("a.o"), try toPath("b.o"), try toPath("c.o")])
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-library", "./a.swift", "./b.swift", "./c.swift", "-module-name", "main", "-target", "x86_64-apple-macosx10.9", "-driver-filelist-threshold=0"],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()
      let job = plannedJobs[3]
      let inputsFlag = job.commandLine.firstIndex(of: .flag("-filelist"))!
      let inputFileListArgument = job.commandLine[job.commandLine.index(after: inputsFlag)]
      guard case let .path(.fileList(_, inputFileList)) = inputFileListArgument else {
        Issue.record("Argument wasn't a filelist")
        return
      }
      guard case let .list(inputs) = inputFileList else {
        Issue.record("FileList wasn't List")
        return
      }
      expectEqual(inputs.count, 3)
      #expect(matchTemporary(inputs[0], "a.o"))
      #expect(matchTemporary(inputs[1], "b.o"))
      #expect(matchTemporary(inputs[2], "c.o"))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-library", "./a.swift", "./b.swift", "./c.swift", "-module-name", "main", "-target", "x86_64-apple-macosx10.9", "-driver-filelist-threshold=0", "-whole-module-optimization", "-num-threads", "1"],
                              env: envVars)
      let plannedJobs = try await driver.planBuild()
      let job = plannedJobs[1]
      let inputsFlag = job.commandLine.firstIndex(of: .flag("-filelist"))!
      let inputFileListArgument = job.commandLine[job.commandLine.index(after: inputsFlag)]
      guard case let .path(.fileList(_, inputFileList)) = inputFileListArgument else {
        Issue.record("Argument wasn't a filelist")
        return
      }
      guard case let .list(inputs) = inputFileList else {
        Issue.record("FileList wasn't List")
        return
      }
      expectEqual(inputs.count, 3)
      #expect(matchTemporary(inputs[0], "a.o"))
      #expect(matchTemporary(inputs[1], "b.o"))
      #expect(matchTemporary(inputs[2], "c.o"))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-typecheck", "a.swift", "b.swift", "-driver-filelist-threshold=0"])
      let plannedJobs = try await driver.planBuild()

      let jobA = plannedJobs[0]
      let mapA = try jobA.commandLine.supplementaryOutputFilemap
      try expectEqual(mapA.entries, [try toPath("a.swift").intern(): [:]])

      let jobB = plannedJobs[1]
      let mapB = try jobB.commandLine.supplementaryOutputFilemap
      try expectEqual(mapB.entries, [try toPath("b.swift").intern(): [:]])
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-typecheck", "-wmo", "a.swift", "b.swift", "-driver-filelist-threshold=0"])
      let plannedJobs = try await driver.planBuild()

      let jobA = plannedJobs[0]
      let mapA = try jobA.commandLine.supplementaryOutputFilemap
      try expectEqual(mapA.entries, [try toPath("a.swift").intern(): [:]])
    }
  }

  @Test func emitLLVMIR() async throws {
    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-irgen", "file.swift"])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(jobs.count == 1)

      expectJobInvocationMatches(jobs[0], .flag("-emit-irgen"))
      #expect(!jobs[0].commandLine.contains("-emit-ir"))
    }

    do {
      var driver = try TestDriver(args: ["swiftc", "-emit-ir", "file.swift"])
      let jobs = try await driver.planBuild().removingAutolinkExtractJobs()
      #expect(jobs.count == 1)

      expectJobInvocationMatches(jobs[0], .flag("-emit-ir"))
      #expect(!jobs[0].commandLine.contains("-emit-irgen"))
    }
  }

  @Test func supplementaryOutputFileMapUsage() async throws {
    // Ensure filenames are escaped properly when using a supplementary output file map
    try await withTemporaryDirectory { path in
      let moduleCachePath = path.appending(component: "ModuleCache")
      try localFileSystem.createDirectory(moduleCachePath)
      let one = path.appending(component: "one.swift")
      let two = path.appending(component: "needs to escape spaces.swift")
      let three = path.appending(component: "another'one.swift")
      let four = path.appending(component: "4.swift")
      try localFileSystem.writeFileContents(one, bytes:
        """
        public struct A {}
        """
      )
      try localFileSystem.writeFileContents(two, bytes:
        """
        struct B {}
        """
      )
      try localFileSystem.writeFileContents(three, bytes:
        """
        struct C {}
        """
      )
      try localFileSystem.writeFileContents(four, bytes:
        """
        struct D {}
        """
      )

      let sdkArgumentsForTesting = (try? Driver.sdkArgumentsForTesting()) ?? []
      let invocationArguments = ["swiftc",
                                 "-parse-as-library",
                                 "-emit-library",
                                 "-driver-filelist-threshold", "0",
                                 "-module-cache-path", moduleCachePath.nativePathString(escaped: false),
                                 "-working-directory", path.nativePathString(escaped: false),
                                 one.nativePathString(escaped: false),
                                 two.nativePathString(escaped: false),
                                 three.nativePathString(escaped: false),
                                 four.nativePathString(escaped: false)] + sdkArgumentsForTesting
      var driver = try TestDriver(args: invocationArguments)
      let jobs = try await driver.planBuild()
      try await driver.run(jobs: jobs)
      #expect(!driver.diagnosticEngine.hasErrors)
    }
  }
}
