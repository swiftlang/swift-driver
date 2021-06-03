//===--------------- IncrementalCompilationTests.swift - Swift Testing ----===//
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

@_spi(Testing) import SwiftDriver
import SwiftOptions
import TestUtilities

// MARK: - Instance variables and initialization
final class IncrementalCompilationTests: XCTestCase {

  var tempDir: AbsolutePath = AbsolutePath("/tmp")

  var derivedDataDir: AbsolutePath {
    tempDir.appending(component: "derivedData")
  }

  let module = "theModule"
  var OFM: AbsolutePath {
    tempDir.appending(component: "OFM.json")
  }
  let baseNamesAndContents = [
    "main": "let foo = 1",
    "other": "let bar = foo"
  ]
  func inputPath(basename: String) -> AbsolutePath {
    tempDir.appending(component: basename + ".swift")
  }
  var inputPathsAndContents: [(AbsolutePath, String)] {
    baseNamesAndContents.map {
      (inputPath(basename: $0.key), $0.value)
    }
  }
  var derivedDataPath: AbsolutePath {
    tempDir.appending(component: "derivedData")
  }
  var masterSwiftDepsPath: AbsolutePath {
    derivedDataPath.appending(component: "\(module)-master.swiftdeps")
  }
  var priorsPath: AbsolutePath {
    derivedDataPath.appending(component: "\(module)-master.priors")
  }
  func swiftDepsPath(basename: String) -> AbsolutePath {
    derivedDataPath.appending(component: "\(basename).swiftdeps")
  }
  var autolinkIncrementalExpectations: [String] {
    [
      "Incremental compilation: Queuing Extracting autolink information for module \(module)",
    ]
  }
  var autolinkLifecycleExpectations: [String] {
    [
      "Starting Extracting autolink information for module \(module)",
      "Finished Extracting autolink information for module \(module)",
    ]
  }
  var commonArgs: [String] {
    [
      "swiftc",
      "-module-name", module,
      "-o", derivedDataPath.appending(component: module + ".o").pathString,
      "-output-file-map", OFM.pathString,
      "-driver-show-incremental",
      "-driver-show-job-lifecycle",
      "-enable-batch-mode",
      //        "-v",
      "-save-temps",
      "-incremental",
    ]
    + inputPathsAndContents.map {$0.0.pathString} .sorted()
  }

  override func setUp() {
    self.tempDir = try! withTemporaryDirectory(removeTreeOnDeinit: false) {$0}
    try! localFileSystem.createDirectory(derivedDataPath)
    OutputFileMapCreator.write(module: module,
                               inputPaths: inputPathsAndContents.map {$0.0},
                               derivedData: derivedDataPath,
                               to: OFM)
    for (base, contents) in baseNamesAndContents {
      write(contents, to: base)
    }
  }

  deinit {
    try? localFileSystem.removeFileTree(tempDir)
  }
}

// MARK: - Misc. tests
extension IncrementalCompilationTests {

  func testOptionsParsing() throws {
    let optionPairs: [(
      Option, (IncrementalCompilationState.IncrementalDependencyAndInputSetup) -> Bool
    )] = [
      (.driverAlwaysRebuildDependents, {$0.alwaysRebuildDependents}),
      (.driverShowIncremental, {$0.reporter != nil}),
      (.driverEmitFineGrainedDependencyDotFileAfterEveryImport, {$0.emitDependencyDotFileAfterEveryImport}),
      (.driverVerifyFineGrainedDependencyGraphAfterEveryImport, {$0.verifyDependencyGraphAfterEveryImport}),
      (.enableIncrementalImports, {$0.isCrossModuleIncrementalBuildEnabled}),
      (.disableIncrementalImports, {!$0.isCrossModuleIncrementalBuildEnabled}),
    ]

    for (driverOption, stateOptionFn) in optionPairs {
      try doABuild(
        "initial",
        checkDiagnostics: false,
        extraArguments: [ driverOption.spelling ],
        expectingRemarks: [],
        whenAutolinking: [])

      guard let sdkArgumentsForTesting = try Driver.sdkArgumentsForTesting()
      else {
        throw XCTSkip("Cannot perform this test on this host")
      }
      var driver = try Driver(args: self.commonArgs + [
        driverOption.spelling,
      ] + sdkArgumentsForTesting)
      _ = try driver.planBuild()
      XCTAssertFalse(driver.diagnosticEngine.hasErrors)
      let state = try XCTUnwrap(driver.incrementalCompilationState)
      XCTAssertTrue(stateOptionFn(state.moduleDependencyGraph.info))
    }
  }

  /// Ensure that autolink output file goes with .o directory, to not prevent incremental omission of
  /// autolink job.
  /// Much of the code below is taking from testLinking(), but uses the output file map code here.
  func testAutolinkOutputPath() {
    var env = ProcessEnv.vars
    env["SWIFT_DRIVER_TESTS_ENABLE_EXEC_PATH_FALLBACK"] = "1"
    env["SWIFT_DRIVER_SWIFT_AUTOLINK_EXTRACT_EXEC"] = "/garbage/swift-autolink-extract"
    env["SWIFT_DRIVER_DSYMUTIL_EXEC"] = "/garbage/dsymutil"

    var driver = try! Driver(
      args: commonArgs
        + ["-emit-library", "-target", "x86_64-unknown-linux"],
      env: env)
    let plannedJobs = try! driver.planBuild()
    let autolinkExtractJob = try! XCTUnwrap(
      plannedJobs
        .filter { $0.kind == .autolinkExtract }
        .first)
    let autoOuts = autolinkExtractJob.outputs.filter {$0.type == .autolink}
    XCTAssertEqual(autoOuts.count, 1)
    let autoOut = autoOuts[0]
    let expected = AbsolutePath(derivedDataPath, "\(module).autolink")
    XCTAssertEqual(autoOut.file.absolutePath, expected)
  }
}

// MARK: - Dot file tests
extension IncrementalCompilationTests {
  func testDependencyDotFiles() throws {
    expectNoDotFiles()
    try buildInitialState(extraArguments: ["-driver-emit-fine-grained-dependency-dot-file-after-every-import"])
    expect(dotFilesFor: [
      "main.swiftdeps",
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
      "other.swiftdeps",
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
    ])
  }

  func testDependencyDotFilesCross() throws {
    expectNoDotFiles()
    try buildInitialState(extraArguments: [
      "-driver-emit-fine-grained-dependency-dot-file-after-every-import",
    ])
    removeDotFiles()
    try checkNoPropagation(extraArguments: [
      "-driver-emit-fine-grained-dependency-dot-file-after-every-import",
    ])

    expect(dotFilesFor: [
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
      "other.swiftdeps",
      DependencyGraphDotFileWriter.moduleDependencyGraphBasename,
    ])
  }

  func expectNoDotFiles() {
    guard localFileSystem.exists(derivedDataDir) else { return }
    try! localFileSystem.getDirectoryContents(derivedDataDir)
      .forEach {derivedFile in
        XCTAssertFalse(derivedFile.hasSuffix("dot"))
      }
  }

  func removeDotFiles() {
    try! localFileSystem.getDirectoryContents(derivedDataDir)
      .filter {$0.hasSuffix(".dot")}
      .map {derivedDataDir.appending(component: $0)}
      .forEach {try! localFileSystem.removeFileTree($0)}
  }

  private func expect(dotFilesFor importedFiles: [String]) {
    let expectedDotFiles = Set(
      importedFiles.enumerated()
      .map { offset, element in "\(element).\(offset).dot" })
    let actualDotFiles = Set(
      try! localFileSystem.getDirectoryContents(derivedDataDir)
      .filter {$0.hasSuffix(".dot")})

    let missingDotFiles = expectedDotFiles.subtracting(actualDotFiles)
      .sortedByDotFileSequenceNumbers()
    let extraDotFiles = actualDotFiles.subtracting(expectedDotFiles)
      .sortedByDotFileSequenceNumbers()

    XCTAssertEqual(missingDotFiles, [])
    XCTAssertEqual(extraDotFiles, [])
  }
}

// MARK: - Post-compile jobs
extension IncrementalCompilationTests {
  /// Ensure that if an output of post-compile job is missing, the job gets rerun.
  func testIncrementalPostCompileJob() throws {
    #if !os(Linux)
    let driver = try XCTUnwrap(buildInitialState(checkDiagnostics: true))
    for postCompileOutput in try driver.postCompileOutputs() {
      let absPostCompileOutput = try XCTUnwrap(postCompileOutput.file.absolutePath)
      try localFileSystem.removeFileTree(absPostCompileOutput)
      XCTAssertFalse(localFileSystem.exists(absPostCompileOutput))
      try checkNullBuild()
      XCTAssertTrue(localFileSystem.exists(absPostCompileOutput))
    }
    #endif
  }
}
fileprivate extension Driver {
  func postCompileOutputs() throws -> [TypedVirtualPath] {
    try XCTUnwrap(incrementalCompilationState).jobsAfterCompiles.flatMap {$0.outputs}
  }
}

// MARK: - Simpler incremental tests
extension IncrementalCompilationTests {

  // FIXME: why does it fail on Linux in CI?
  func testIncrementalDiagnostics() throws {
    #if !os(Linux)
    try testIncremental(checkDiagnostics: true)
    #endif
  }

  func testIncremental() throws {
    try testIncremental(checkDiagnostics: false)
  }

  func testIncremental(checkDiagnostics: Bool) throws {
    try buildInitialState(checkDiagnostics: checkDiagnostics)
#if true // sometimes want to skip for debugging
    try checkNullBuild(checkDiagnostics: checkDiagnostics)
    try checkNoPropagation(checkDiagnostics: checkDiagnostics)
    try checkReactionToTouchingAll(checkDiagnostics: checkDiagnostics)
#endif
    try checkPropagationOfTopLevelChange(checkDiagnostics: checkDiagnostics)
  }

  // FIXME: Expect failure in Linux in CI just as testIncrementalDiagnostics
  func testAlwaysRebuildDependents() throws {
#if !os(Linux)
    try buildInitialState(checkDiagnostics: true)
    try checkAlwaysRebuildDependents(checkDiagnostics: true)
#endif
  }

  /// Ensure that the mod date of the input comes back exactly the same via the build-record.
  /// Otherwise the up-to-date calculation in `IncrementalCompilationState` will fail.
  func testBuildRecordDateAccuracy() throws {
    try buildInitialState()
    try (1...10).forEach { n in
      try checkNullBuild(checkDiagnostics: true)
    }
  }
}

// MARK: - Test adding an input
extension IncrementalCompilationTests {

  func testAddingInput() throws {
#if !os(Linux)
  try testAddingInput(newInput: "another", defining: "nameInAnother")
#endif
  }

  /// Test the addition of an input file
  ///
  /// - Parameters:
  ///   - newInput: basename without extension of new input file
  ///   - topLevelName: a new top level name defined in the new input
  private func testAddingInput(newInput: String, defining topLevelName: String
  ) throws {
    let initial = try buildInitialState(checkDiagnostics: true).moduleDependencyGraph()
    initial.ensureOmits(sourceBasenameWithoutExt: newInput)
    initial.ensureOmits(name: topLevelName)

    write("func \(topLevelName)() {}", to: newInput)
    let newInputsPath = inputPath(basename: newInput)
    OutputFileMapCreator.write(module: module,
                               inputPaths: inputPathsAndContents.map {$0.0} + [newInputsPath],
                               derivedData: derivedDataPath,
                               to: OFM)
    try checkReactionToAddingInput(newInput: newInput, definingTopLevel: topLevelName)
    try checkRestorationOfIncrementalityAfterAddition(newInput: newInput, definingTopLevel: topLevelName)
  }
}

// MARK: - Incremental file removal tests
/// In order to ensure robustness, test what happens under various conditions when a source file is
/// removed.
/// The following is a lot of work to get something that prints nicely. Need an enum with both a string and an int value.
fileprivate enum RemovalTestOption: String, CaseIterable, Comparable, Hashable, CustomStringConvertible {
  case
  removeInputFromInvocation,
  removeSourceFile,
  removePreviouslyAddedInputFromOutputFileMap,
  removeSwiftDepsFile,
  restoreBadPriors

  private static let byInt  = [Int: Self](uniqueKeysWithValues: allCases.enumerated().map{($0, $1)})
  private static let intFor = [Self: Int](uniqueKeysWithValues: allCases.enumerated().map{($1, $0)})

  var intValue: Int {Self.intFor[self]!}
  init(fromInt i: Int) {self = Self.byInt[i]!}

  static func < (lhs: RemovalTestOption, rhs: RemovalTestOption) -> Bool {
    lhs.intValue < rhs.intValue
  }
  var mask: Int { 1 << intValue}
  static let maxIntValue = allCases.map {$0.intValue} .max()!
  static let maxCombinedValue = (1 << maxIntValue) - 1

  var description: String { rawValue }
}

/// Only 5 elements, an array is fine
fileprivate typealias RemovalTestOptions = [RemovalTestOption]

extension RemovalTestOptions {
  fileprivate static let allCombinations: [RemovalTestOptions] =
  (0...RemovalTestOption.maxCombinedValue) .map(decoding)

  fileprivate static func decoding(_ bits: Int) -> Self {
    RemovalTestOption.allCases.filter { opt in
      (1 << opt.intValue) & bits != 0
    }
  }
}

extension IncrementalCompilationTests {
  /// While all cases are being made to work, just test for now in known good cases
  func testRemovalInPassingCases() throws {
    try testRemoval(includeFailingCombos: false)
  }

  /// Someday, turn this test on and test all cases
  func testRemovalInAllCases() throws {
    throw XCTSkip("unimplemented")
    try testRemoval(includeFailingCombos: true)
  }

  func testRemoval(includeFailingCombos: Bool) throws {
#if !os(Linux)
    let knownGoodCombos: [[RemovalTestOption]] = [
      [.removeInputFromInvocation],
    ]
    for optionsToTest in RemovalTestOptions.allCombinations {
      if knownGoodCombos.contains(optionsToTest) {
        try testRemoval(optionsToTest)
      }
      else if includeFailingCombos {
          try testRemoval(optionsToTest)
      }
    }
#endif
  }

  private func testRemoval(_ options: RemovalTestOptions) throws {
    guard !options.isEmpty else {return}
    print("*** testRemoval \(options) ***", to: &stderrStream); stderrStream.flush()

    let newInput = "another"
    let topLevelName = "nameInAnother"
    try testAddingInput(newInput: newInput, defining: topLevelName)
    if options.contains(.removeSourceFile) {
      removeInput(newInput)
    }
    if options.contains(.removeSwiftDepsFile) {
      removeSwiftDeps(newInput)
    }
    if options.contains(.removePreviouslyAddedInputFromOutputFileMap) {
      // FACTOR
      OutputFileMapCreator.write(module: module,
                                 inputPaths: inputPathsAndContents.map {$0.0},
                                 derivedData: derivedDataPath,
                                 to: OFM)
    }
    let includeInputInInvocation = !options.contains(.removeInputFromInvocation)
    do {
      let wrapperFn = options.contains(.restoreBadPriors)
      ? preservingPriorsDo
      : {try $0()}
      try wrapperFn {
        try self.checkNonincrementalAfterRemoving(
          removedInput: newInput,
          defining: topLevelName,
          includeInputInInvocation: includeInputInInvocation)
      }
    }
    try checkRestorationOfIncrementalityAfterRemoval(
      removedInput: newInput,
      defining: topLevelName,
      includeInputInInvocation: includeInputInInvocation,
      afterRestoringBadPriors: options.contains(.restoreBadPriors))
  }
}

// MARK: - Incremental test stages
extension IncrementalCompilationTests {
  /// Setup the initial post-build state.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  /// - Returns: The `Driver` object
  @discardableResult
  private func buildInitialState(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) throws -> Driver {
    try doABuild(
      "initial",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expectingRemarks: [
        // Leave off the part after the colon because it varies on Linux:
        // MacOS: The operation could not be completed. (TSCBasic.FileSystemError error 3.).
        // Linux: The operation couldn’t be completed. (TSCBasic.FileSystemError error 3.)
        "Enabling incremental cross-module building",
        "Incremental compilation: Incremental compilation could not read build record at",
        "Incremental compilation: Disabling incremental build: could not read build record",
        "Incremental compilation: Created dependency graph from swiftdeps files",
        "Found 2 batchable jobs",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 2 constituents: main.swift, other.swift",
        "Starting Compiling main.swift, other.swift",
        "Finished Compiling main.swift, other.swift",
        "Incremental compilation: Scheduling all post-compile jobs because something was compiled",
        "Starting Linking theModule",
        "Finished Linking theModule",
      ],
      whenAutolinking: autolinkLifecycleExpectations)
  }

  /// Try a build with no changes.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  private func checkNullBuild(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) throws {
    try doABuild(
      "as is",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expectingRemarks: [
        "Enabling incremental cross-module building",
        "Incremental compilation: Read dependency graph",
        "Incremental compilation: May skip current input:  {compile: main.o <= main.swift}",
        "Incremental compilation: May skip current input:  {compile: other.o <= other.swift}",
        "Incremental compilation: Skipping input:  {compile: main.o <= main.swift}",
        "Incremental compilation: Skipping input:  {compile: other.o <= other.swift}",
        "Skipped Compiling main.swift",
        "Skipped Compiling other.swift",
        "Incremental compilation: Skipping job: Linking theModule; oldest output is current",
      ],
      whenAutolinking: [])
  }

  /// Check reaction to touching a non-propagating input.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  private func checkNoPropagation(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) throws {
    touch("other")
    try doABuild(
      "touch other; non-propagating",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expectingRemarks: [
        "Enabling incremental cross-module building",
        "Incremental compilation: May skip current input:  {compile: main.o <= main.swift}",
        "Incremental compilation: Scheduing changed input  {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing (initial):  {compile: other.o <= other.swift}",
        "Incremental compilation: not scheduling dependents of other.swift; unknown changes",
        "Incremental compilation: Skipping input:  {compile: main.o <= main.swift}",
        "Incremental compilation: Read dependency graph",
        "Found 1 batchable job",
        "Forming into 1 batch",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 1 constituents: other.swift",
        "Starting Compiling other.swift",
        "Finished Compiling other.swift",
        "Incremental compilation: Scheduling all post-compile jobs because something was compiled",
        "Starting Linking theModule",
        "Finished Linking theModule",
        "Skipped Compiling main.swift",
    ],
    whenAutolinking: autolinkLifecycleExpectations)
  }

  /// Check reaction to touching both inputs.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  private func checkReactionToTouchingAll(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
 ) throws {
    touch("main")
    touch("other")
    try doABuild(
      "touch both; non-propagating",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expectingRemarks: [
        "Enabling incremental cross-module building",
        "Incremental compilation: Read dependency graph",
        "Incremental compilation: Scheduing changed input  {compile: main.o <= main.swift}",
        "Incremental compilation: Scheduing changed input  {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing (initial):  {compile: main.o <= main.swift}",
        "Incremental compilation: Queuing (initial):  {compile: other.o <= other.swift}",
        "Incremental compilation: not scheduling dependents of main.swift; unknown changes",
        "Incremental compilation: not scheduling dependents of other.swift; unknown changes",
        "Found 2 batchable jobs",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 2 constituents: main.swift, other.swift",
        "Starting Compiling main.swift, other.swift",
        "Finished Compiling main.swift, other.swift",
        "Incremental compilation: Scheduling all post-compile jobs because something was compiled",
        "Starting Linking theModule",
        "Finished Linking theModule",
    ],
    whenAutolinking: autolinkLifecycleExpectations)
  }

  /// Check reaction to changing a top-level declaration.
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  private func checkPropagationOfTopLevelChange(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) throws {
    replace(contentsOf: "main", with: "let foo = \"hello\"")
    try doABuild(
      "replace contents of main; propagating into 2nd wave",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expectingRemarks: [
        "Enabling incremental cross-module building",
        "Incremental compilation: Read dependency graph",
        "Incremental compilation: Scheduing changed input  {compile: main.o <= main.swift}",
        "Incremental compilation: May skip current input:  {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing (initial):  {compile: main.o <= main.swift}",
        "Incremental compilation: not scheduling dependents of main.swift; unknown changes",
        "Incremental compilation: Skipping input:  {compile: other.o <= other.swift}",
        "Found 1 batchable job",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Forming batch job from 1 constituents: main.swift",
        "Starting Compiling main.swift",
        "Finished Compiling main.swift",
        "Incremental compilation: Fingerprint changed for interface of source file main.swiftdeps in main.swiftdeps",
        "Incremental compilation: Fingerprint changed for implementation of source file main.swiftdeps in main.swiftdeps",
        "Incremental compilation: Traced: interface of source file main.swiftdeps in main.swift -> interface of top-level name 'foo' in main.swift -> implementation of source file other.swiftdeps in other.swift",
        "Incremental compilation: Queuing because of dependencies discovered later:  {compile: other.o <= other.swift}",
        "Incremental compilation: Scheduling invalidated  {compile: other.o <= other.swift}",
        "Found 1 batchable job",
        "Forming into 1 batch",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 1 constituents: other.swift",
        "Starting Compiling other.swift",
        "Finished Compiling other.swift",
        "Incremental compilation: Scheduling all post-compile jobs because something was compiled",
        "Starting Linking theModule",
        "Finished Linking theModule",
      ],
      whenAutolinking: autolinkLifecycleExpectations)
  }

  /// Check functioning of `-driver-always-rebuild-dependents`
  ///
  /// - Parameters:
  ///   - checkDiagnostics: If true verify the diagnostics
  ///   - extraArguments: Additional command-line arguments
  private func checkAlwaysRebuildDependents(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) throws {
    touch("main")
    let extraArgument = "-driver-always-rebuild-dependents"
    try doABuild(
      "touch main; non-propagating but \(extraArgument)",
      checkDiagnostics: checkDiagnostics,
      extraArguments: [extraArgument],
      expectingRemarks: [
        "Enabling incremental cross-module building",
        "Incremental compilation: Read dependency graph",
        "Incremental compilation: May skip current input:  {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing (initial):  {compile: main.o <= main.swift}",
        "Incremental compilation: scheduling dependents of main.swift; -driver-always-rebuild-dependents",
        "Incremental compilation: Traced: interface of top-level name 'foo' in main.swift -> implementation of source file other.swiftdeps in other.swift",
        "Incremental compilation: Found dependent of main.swift:  {compile: other.o <= other.swift}",
        "Incremental compilation: Scheduing changed input  {compile: main.o <= main.swift}",
        "Incremental compilation: Immediately scheduling dependent on main.swift  {compile: other.o <= other.swift}",
        "Incremental compilation: Queuing because of the initial set:  {compile: other.o <= other.swift}",
        "Found 2 batchable jobs",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 2 constituents: main.swift, other.swift",
        "Incremental compilation: Scheduling all post-compile jobs because something was compiled",
        "Starting Compiling main.swift, other.swift",
        "Finished Compiling main.swift, other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
      ],
      whenAutolinking: autolinkLifecycleExpectations)
  }

  /// Check reaction to adding an input file.
  ///
  /// - Parameters:
  ///   - newInput: The basename without extension of the new file
  ///   - topLevelName: The top-level decl name added by the new file
  private func checkReactionToAddingInput(
    newInput: String,
    definingTopLevel topLevelName: String
  ) throws {
    let newInputsPath = inputPath(basename: newInput)
    let graph = try doABuild(
      "after addition of \(newInput)",
      checkDiagnostics: true,
      extraArguments: [newInputsPath.pathString],
      expectingRemarks: [
        "Incremental compilation: Read dependency graph",
        "Incremental compilation: Enabling incremental cross-module building",
        "Incremental compilation: May skip current input:  {compile: main.o <= main.swift}",
        "Incremental compilation: May skip current input:  {compile: other.o <= other.swift}",
        "Incremental compilation: Scheduling new  {compile: \(newInput).o <= \(newInput).swift}",
        "Incremental compilation: Has malformed dependency source; will queue  {compile: \(newInput).o <= \(newInput).swift}",
        "Incremental compilation: Missing an output; will queue  {compile: \(newInput).o <= \(newInput).swift}",
        "Incremental compilation: Queuing (initial):  {compile: \(newInput).o <= \(newInput).swift}",
        "Incremental compilation: not scheduling dependents of \(newInput).swift: no entry in build record or dependency graph",
        "Incremental compilation: Skipping input:  {compile: main.o <= main.swift}",
        "Incremental compilation: Skipping input:  {compile: other.o <= other.swift}",
        "Found 1 batchable job",
        "Forming into 1 batch",
        "Adding {compile: \(newInput).swift} to batch 0",
        "Forming batch job from 1 constituents: \(newInput).swift",
        "Starting Compiling \(newInput).swift",
        "Finished Compiling \(newInput).swift",
        "Incremental compilation: New definition: interface of source file \(newInput).swiftdeps in \(newInput).swiftdeps",
        "Incremental compilation: New definition: implementation of source file \(newInput).swiftdeps in \(newInput).swiftdeps",
        "Incremental compilation: New definition: interface of top-level name '\(topLevelName)' in \(newInput).swiftdeps",
        "Incremental compilation: New definition: implementation of top-level name '\(topLevelName)' in \(newInput).swiftdeps",
        "Incremental compilation: Scheduling all post-compile jobs because something was compiled",
        "Starting Linking theModule",
        "Finished Linking theModule",
        "Skipped Compiling main.swift",
        "Skipped Compiling other.swift",
      ],
      whenAutolinking: autolinkLifecycleExpectations)
      .moduleDependencyGraph()

    XCTAssert(graph.contains(sourceBasenameWithoutExt: newInput))
    XCTAssert(graph.contains(name: topLevelName))
  }

  /// Ensure that incremental builds happen after an addition.
  ///
  /// - Parameters:
  ///   - newInput: The basename without extension of the new file
  ///   - topLevelName: The top-level decl name added by the new file
  private func checkRestorationOfIncrementalityAfterAddition(
    newInput: String,
    definingTopLevel topLevelName: String
  ) throws {
    let newInputPath = inputPath(basename: newInput)
    let graph = try doABuild(
      "after after addition of \(newInput)",
      checkDiagnostics: true,
      extraArguments: [newInputPath.pathString],
      expectingRemarks: [
        "Incremental compilation: Read dependency graph",
        "Incremental compilation: Enabling incremental cross-module building",
        "Incremental compilation: May skip current input:  {compile: main.o <= main.swift}",
        "Incremental compilation: May skip current input:  {compile: other.o <= other.swift}",
        "Incremental compilation: May skip current input:  {compile: \(newInput).o <= \(newInput).swift}",
        "Incremental compilation: Skipping input:  {compile: main.o <= main.swift}",
        "Incremental compilation: Skipping input:  {compile: other.o <= other.swift}",
        "Incremental compilation: Skipping input:  {compile: \(newInput).o <= \(newInput).swift}",
        "Incremental compilation: Skipping job: Linking theModule; oldest output is current",
        "Skipped Compiling \(newInput).swift",
        "Skipped Compiling main.swift",
        "Skipped Compiling other.swift",
      ],
      whenAutolinking: autolinkLifecycleExpectations)
      .moduleDependencyGraph()

    XCTAssert(graph.contains(sourceBasenameWithoutExt: newInput))
    XCTAssert(graph.contains(name: topLevelName))
  }

  /// Check fallback to nonincremental build after a removal.
  ///
  /// - Parameters:
  ///   - newInput: The basename without extension of the removed input
  ///   - defining: A top level name defined by the removed file
  ///   - includeInputInInvocation: include the removed input in the invocation
  private func checkNonincrementalAfterRemoving(
    removedInput: String,
    defining topLevelName: String,
    includeInputInInvocation: Bool
  ) throws {
    let extraArguments = includeInputInInvocation
      ? [inputPath(basename: removedInput).pathString]
      : []
    try doABuild(
      "after removal of \(removedInput)",
      checkDiagnostics: true,
      extraArguments: extraArguments,
      expectingRemarks: [
        "Incremental compilation: Incremental compilation has been disabled, because the following inputs were used in the previous compilation but not in this one: \(removedInput).swift",
        "Found 2 batchable jobs",
        "Forming into 1 batch",
        "Adding {compile: main.swift} to batch 0",
        "Adding {compile: other.swift} to batch 0",
        "Forming batch job from 2 constituents: main.swift, other.swift",
        "Starting Compiling main.swift, other.swift",
        "Finished Compiling main.swift, other.swift",
        "Starting Linking theModule",
        "Finished Linking theModule",
      ],
      whenAutolinking: autolinkLifecycleExpectations)
      .verifyNoGraph()

    verifyNoPriors()
  }

  /// Ensure that incremental builds happen after a removal.
  ///
  /// - Parameters:
  ///   - newInput: The basename without extension of the new file
  ///   - topLevelName: The top-level decl name added by the new file
  @discardableResult
  private func checkRestorationOfIncrementalityAfterRemoval(
    removedInput: String,
    defining topLevelName: String,
    includeInputInInvocation: Bool,
    afterRestoringBadPriors: Bool
  ) throws -> ModuleDependencyGraph {
    let extraArguments = includeInputInInvocation
      ? [inputPath(basename: removedInput).pathString]
      : []
    let expectations = afterRestoringBadPriors
    ? [
       "Incremental compilation: Read dependency graph",
       "Incremental compilation: Enabling incremental cross-module building",
       "Incremental compilation: May skip current input:  {compile: main.o <= main.swift}",
       "Incremental compilation: May skip current input:  {compile: other.o <= other.swift}",
       "Incremental compilation: Skipping input:  {compile: main.o <= main.swift}",
       "Incremental compilation: Skipping input:  {compile: other.o <= other.swift}",
       "Incremental compilation: Skipping job: Linking theModule; oldest output is current",
       "Skipped Compiling main.swift",
       "Skipped Compiling other.swift",
    ].map(Diagnostic.Message.remark)
    : [
      "Incremental compilation: Created dependency graph from swiftdeps files",
      "Incremental compilation: Enabling incremental cross-module building",
      "Incremental compilation: May skip current input:  {compile: main.o <= main.swift}",
      "Incremental compilation: May skip current input:  {compile: other.o <= other.swift}",
      "Incremental compilation: Skipping input:  {compile: main.o <= main.swift}",
      "Incremental compilation: Skipping input:  {compile: other.o <= other.swift}",
      "Incremental compilation: Skipping job: Linking theModule; oldest output is current",
      "Skipped Compiling main.swift",
      "Skipped Compiling other.swift",
    ].map(Diagnostic.Message.remark)
    let graph = try doABuild(
      "after after removal of \(removedInput)",
      checkDiagnostics: true,
      extraArguments: extraArguments,
      expecting: expectations,
      expectingWhenAutolinking: autolinkLifecycleExpectations.map(Diagnostic.Message.remark))
      .moduleDependencyGraph()

    graph.verifyGraph()
    graph.ensureOmits(sourceBasenameWithoutExt: removedInput)
    graph.ensureOmits(name: topLevelName)

    return graph
  }
}

// MARK: - Incremental test perturbation helpers
extension IncrementalCompilationTests {
  private func touch(_ name: String) {
    print("*** touching \(name) ***", to: &stderrStream); stderrStream.flush()
    let (path, contents) = try! XCTUnwrap(inputPathsAndContents.filter {$0.0.pathString.contains(name)}.first)
    try! localFileSystem.writeFileContents(path) { $0 <<< contents }
  }

  private func removeInput(_ name: String) {
    print("*** removing input \(name) ***", to: &stderrStream); stderrStream.flush()
    try! localFileSystem.removeFileTree(inputPath(basename: name))
  }

  private func removeSwiftDeps(_ name: String) {
    print("*** removing swiftdeps \(name) ***", to: &stderrStream); stderrStream.flush()
    let swiftDepsPath = swiftDepsPath(basename: name)
    XCTAssert(localFileSystem.exists(swiftDepsPath))
    try! localFileSystem.removeFileTree(swiftDepsPath)
  }

  private func replace(contentsOf name: String, with replacement: String ) {
    print("*** replacing \(name) ***", to: &stderrStream); stderrStream.flush()
    let path = inputPath(basename: name)
    let previousContents = try! localFileSystem.readFileContents(path).cString
    try! localFileSystem.writeFileContents(path) { $0 <<< replacement }
    let newContents = try! localFileSystem.readFileContents(path).cString
    XCTAssert(previousContents != newContents, "\(path.pathString) unchanged after write")
    XCTAssert(replacement == newContents, "\(path.pathString) failed to write")
  }

  private func write(_ contents: String, to basename: String) {
    print("*** writing \(contents) to \(basename)")
    try! localFileSystem.writeFileContents(inputPath(basename: basename)) {
      $0 <<< contents
    }
  }

  private func readPriors() -> ByteString? {
    try? localFileSystem.readFileContents(priorsPath)
  }

  private func writePriors( _ contents: ByteString) {
    try! localFileSystem.writeFileContents(priorsPath, bytes: contents)
  }

  private func preservingPriorsDo(_ fn: () throws -> Void ) throws {
    let contents = try XCTUnwrap(readPriors())
    try fn()
    writePriors(contents)
  }

  private func verifyNoPriors() {
    XCTAssertNil(readPriors().map {"\($0.count) bytes"}, "Should not have found priors")
  }
}

// MARK: - Graph inspection
fileprivate extension Driver {
  func moduleDependencyGraph() throws -> ModuleDependencyGraph {
    do {return try XCTUnwrap(incrementalCompilationState?.moduleDependencyGraph) }
    catch {
      XCTFail("no graph")
      throw error
    }
  }
  func verifyNoGraph() {
    XCTAssertNil(incrementalCompilationState)
  }
}

fileprivate extension ModuleDependencyGraph {
  /// A convenience for testing
  var allNodes: [Node] {
    var nodes = [Node]()
    nodeFinder.forEachNode {nodes.append($0)}
    return nodes
  }
  func contains(sourceBasenameWithoutExt target: String) -> Bool {
    allNodes.contains {$0.contains(sourceBasenameWithoutExt: target)}
  }
  func contains(name target: String) -> Bool {
    allNodes.contains {$0.contains(name: target)}
  }
  func ensureOmits(sourceBasenameWithoutExt target: String) {
    nodeFinder.forEachNode { node in
      XCTAssertFalse(node.contains(sourceBasenameWithoutExt: target),
                     "graph should omit source: \(target)")
    }
  }
  func ensureOmits(name: String) {
    nodeFinder.forEachNode { node in
      XCTAssertFalse(node.contains(name: name),
                     "graph should omit decl named: \(name)")
    }
  }
}

fileprivate extension ModuleDependencyGraph.Node {
  func contains(sourceBasenameWithoutExt target: String) -> Bool {
    switch key.designator {
    case .sourceFileProvide(name: let name):
      return (try? VirtualPath(path: name))
        .map {$0.basenameWithoutExt == target}
      ?? false
    case .externalDepend(let externalDependency):
      return externalDependency.path.map {
        $0.basenameWithoutExt == target
      }
      ?? false
    case .topLevel, .dynamicLookup, .nominal, .member, .potentialMember:
      return false
    }
  }

  func contains(name target: String) -> Bool {
    switch key.designator {
    case .topLevel(name: let name),
      .dynamicLookup(name: let name):
      return name == target
    case .externalDepend, .sourceFileProvide:
      return false
    case .nominal(context: let context),
         .potentialMember(context: let context):
      return context.range(of: target) != nil
    case .member(context: let context, name: let name):
      return context.range(of: target) != nil || name == target
    }
  }
}

// MARK: - Build helpers
extension IncrementalCompilationTests {
  @discardableResult
  func doABuild(_ message: String,
                checkDiagnostics: Bool,
                extraArguments: [String],
                expectingRemarks texts: [String],
                whenAutolinking: [String]
  ) throws -> Driver {
    try doABuild(
      message,
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expecting: texts.map {.remark($0)},
      expectingWhenAutolinking: whenAutolinking.map {.remark($0)})
  }

  @discardableResult
  func doABuild(_ message: String,
                checkDiagnostics: Bool,
                extraArguments: [String],
                expecting expectations: [Diagnostic.Message],
                expectingWhenAutolinking autolinkExpectations: [Diagnostic.Message]
  ) throws -> Driver {
    print("*** starting build \(message) ***", to: &stderrStream); stderrStream.flush()

    guard let sdkArgumentsForTesting = try Driver.sdkArgumentsForTesting()
    else {
      throw XCTSkip("Cannot perform this test on this host")
    }
    let allArgs = commonArgs + extraArguments + sdkArgumentsForTesting

    return try checkDiagnostics
    ? doABuild(expecting: expectations,
               expectingWhenAutolinking: autolinkExpectations,
               arguments: allArgs)
    : doABuildWithoutExpectations(arguments: allArgs)
  }

  private func doABuild(
    expecting expectations: [Diagnostic.Message],
    expectingWhenAutolinking autolinkExpectations: [Diagnostic.Message],
    arguments: [String]
  ) throws -> Driver {
    try assertDriverDiagnostics(args: arguments) {
      driver, verifier in
      verifier.forbidUnexpected(.error, .warning, .note, .remark, .ignored)
      expectations.forEach {verifier.expect($0)}
      if driver.isAutolinkExtractJobNeeded {
        autolinkExpectations.forEach {verifier.expect($0)}
      }
      doTheCompile(&driver)
      return driver
    }
  }

  private func doABuildWithoutExpectations( arguments: [String]
  ) throws -> Driver {
    // If not checking, print out the diagnostics
    let diagnosticEngine = DiagnosticsEngine(handlers: [
      {print($0, to: &stderrStream); stderrStream.flush()}
    ])
    var driver = try Driver(args: arguments, env: ProcessEnv.vars,
                      diagnosticsEngine: diagnosticEngine,
                      fileSystem: localFileSystem)
    doTheCompile(&driver)
    // Add a newline after any diagnostics for readability
    print("", to: &stderrStream); stderrStream.flush()
    return driver
  }

  private func doTheCompile(_ driver: inout Driver) {
    let jobs = try! driver.planBuild()
    try? driver.run(jobs: jobs)
  }
}
