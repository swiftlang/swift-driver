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
  fileprivate var autolinkIncrementalExpectations: [Diagnostic.Message] {
      .queuingExtractingAutolink(module)
  }
  fileprivate var autolinkLifecycleExpectations: [Diagnostic.Message] {
      .extractingAutolink(module)
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
      "-no-color-diagnostics",
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
        expecting: [],
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

  func testSymlinkModification() throws {
    // Remap
    // main.swift -> links/main.swift
    // other.swift -> links/other.swift
    for (file, _) in self.inputPathsAndContents {
      try localFileSystem.createDirectory(tempDir.appending(component: "links"))
      let linkTarget = tempDir.appending(component: "links").appending(component: file.basename)
      try localFileSystem.move(from: file, to: linkTarget)
      try localFileSystem.removeFileTree(file)
      try localFileSystem.createSymbolicLink(file, pointingAt: linkTarget, relative: false)
    }
    try buildInitialState()
    try checkReactionToTouchingSymlinks(checkDiagnostics: true)
    try checkReactionToTouchingSymlinkTargets(checkDiagnostics: true)
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
  static let maxCombinedValue = (1 << (maxIntValue + 1)) - 1

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
    setUp() // clear derived data, restore output file map
    print("\n*** testRemoval \(options) ***", to: &stderrStream); stderrStream.flush()

    let newInput = "another"
    let topLevelName = "nameInAnother"
    try testAddingInput(newInput: newInput, defining: topLevelName)

    let removeInputFromInvocation = options.contains(.removeInputFromInvocation)
    let removeSwiftDepsFile = options.contains(.removeSwiftDepsFile)
    let restoreBadPriors = options.contains(.restoreBadPriors)
    do {
      let wrapperFn = options.contains(.restoreBadPriors)
      ? preservingPriorsDo
      : {try $0()}
      try wrapperFn {
        try self.checkNonincrementalAfterRemoving(
          removedInput: newInput,
          defining: topLevelName,
          removeInputFromInvocation: removeInputFromInvocation,
          removeSwiftDepsFile: removeSwiftDepsFile)
      }
    }
    try checkRestorationOfIncrementalityAfterRemoval(
      removedInput: newInput,
      defining: topLevelName,
      removeInputFromInvocation: removeInputFromInvocation,
      removeSwiftDepsFile: removeSwiftDepsFile,
      afterRestoringBadPriors: restoreBadPriors)
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
      expecting: [
        // Leave off the part after the colon because it varies on Linux:
        // MacOS: The operation could not be completed. (TSCBasic.FileSystemError error 3.).
        // Linux: The operation couldn’t be completed. (TSCBasic.FileSystemError error 3.)
        .enablingCrossModule,
        .cannotReadBuildRecord,
        .disablingIncrementalCannotReadBuildRecord,
        .createdGraphFromSwiftdeps,
        .findingBatchingCompiling("main", "other"),
        .schedLinking,
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
      expecting: [
        .enablingCrossModule,
        .readGraph,
        .maySkip("main", "other"),
        .skipping("main", "other"),
        .skipped("main", "other"),
        .skippingLinking,
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
      expecting: [
        .enablingCrossModule,
        .maySkip("main"),
        .schedulingChanged("other"),
        .queuingInitial("other"),
        .notSchedulingDependentsUnknownChanges("other"),
        .skipping("main"),
        .readGraph,
        .findingBatchingCompiling("other"),
        .schedLinking,
        .skipped("main"),
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
      expecting: [
        .enablingCrossModule,
        .readGraph,
        .schedulingChanged("main", "other"),
        .queuingInitial("main", "other"),
        .notSchedulingDependentsUnknownChanges("main", "other"),
        .findingBatchingCompiling("main", "other"),
        .schedLinking,
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
      expecting: [
        .readGraph,
        .enablingCrossModule,
        .schedulingChanged("main"),
        .maySkip("other"),
        .queuingInitial("main"),
        .notSchedulingDependentsUnknownChanges("main"),
        .skipping("other"),
        .findingBatchingCompiling("main"),
        .fingerprintChanged(.interface, "main"),
        .fingerprintChanged(.implementation, "main"),
        .remarks(
          "Incremental compilation: Traced: interface of source file main.swiftdeps in main.swift -> interface of top-level name 'foo' in main.swift -> implementation of source file other.swiftdeps in other.swift",
          "Incremental compilation: Queuing because of dependencies discovered later:  {compile: other.o <= other.swift}",
          "Incremental compilation: Scheduling invalidated  {compile: other.o <= other.swift}"),
        .findingBatchingCompiling("other"),
        .schedLinking,
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
      expecting: [
        .enablingCrossModule,
        .readGraph,
        .maySkip("other"),
        .queuingInitial("main"),
        .schedulingAlwaysRebuild("main"),
        .remarks(
          "Incremental compilation: Traced: interface of top-level name 'foo' in main.swift -> implementation of source file other.swiftdeps in other.swift",
          "Incremental compilation: Found dependent of main.swift:  {compile: other.o <= other.swift}"),
        .schedulingChanged("main"),
        .remarks(
          "Incremental compilation: Immediately scheduling dependent on main.swift  {compile: other.o <= other.swift}",
          "Incremental compilation: Queuing because of the initial set:  {compile: other.o <= other.swift}"),
        .findingAndFormingBatch(2),
        .addingToBatchThenForming("main", "other"),
        .schedulingPostCompileJobs,
        .compiling("main", "other"),
        .linking,
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
      expecting: [
        .readGraph,
        .enablingCrossModule,
        .maySkip("main", "other"),
        .schedulingNew(newInput),
        .remarks(
          "Incremental compilation: Has malformed dependency source; will queue  {compile: \(newInput).o <= \(newInput).swift}"),
        .missing(newInput),
        .queuingInitial(newInput),
        .notSchedulingDependentsNoEntry(newInput),
        .skipping("main", "other"),
        .findingBatchingCompiling(newInput),
        .newDefinitionOfSourceFile(.interface,      newInput),
        .newDefinitionOfSourceFile(.implementation, newInput),
        .newDefinitionOfTopLevelName(.interface,      name: topLevelName, input: newInput),
        .newDefinitionOfTopLevelName(.implementation, name: topLevelName, input: newInput),
        .schedLinking,
        .skipped("main", "other"),
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
      expecting: [
        .readGraph,
        .enablingCrossModule,
        .maySkip("main", "other", newInput),
        .skipping("main", "other", newInput),
        .skippingLinking,
        .skipped(newInput, "main", "other"),
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
    removeInputFromInvocation: Bool,
    removeSwiftDepsFile: Bool
  ) throws {
    let extraArguments = removeInputFromInvocation
    ? [] : [inputPath(basename: removedInput).pathString]

    if removeSwiftDepsFile {
      removeSwiftDeps(removedInput)
    }
    let expectations: [[Diagnostic.Message]]
    switch (removeInputFromInvocation, removeSwiftDepsFile) {
    case (false, false):
      expectations = [
        .readGraphAndSkipAll("main", "other", removedInput)
      ]
    case
      (true, false),
      (true, true):
      expectations = [
        .remarks(
          "Incremental compilation: Incremental compilation has been disabled, because the following inputs were used in the previous compilation but not in this one: \(removedInput).swift"),
        .findingBatchingCompiling("main", "other"),
        .linking,
      ]
    case (false, true):
      expectations = [
        .readGraph,
        .enablingCrossModule,
        .maySkip("main", "other", removedInput),
        .missing(removedInput),
        .queuingInitial(removedInput),
        .skipping("main", "other"),
        .findingBatchingCompiling(removedInput),
        .schedulingPostCompileJobs,
        .linking,
        .skipped("main", "other"),
      ]
    }

    let driver = try doABuild(
      "after removal of \(removedInput)",
      checkDiagnostics: true,
      extraArguments: extraArguments,
      expecting: expectations,
      whenAutolinking: autolinkLifecycleExpectations)

    if removeInputFromInvocation {
      driver.verifyNoGraph()
      verifyNoPriors()
    }
    else {
      let graph = try driver.moduleDependencyGraph()
      graph.verifyGraph()
      XCTAssert(graph.contains(sourceBasenameWithoutExt: removedInput))
      XCTAssert(graph.contains(name: topLevelName))
    }
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
    removeInputFromInvocation: Bool,
    removeSwiftDepsFile: Bool,
    afterRestoringBadPriors: Bool
  ) throws -> ModuleDependencyGraph {
    let extraArguments = removeInputFromInvocation
    ? [] : [inputPath(basename: removedInput).pathString]
    let inputs = ["main", "other"] + (removeInputFromInvocation ? [] : [removedInput])
    let expectations: [[Diagnostic.Message]]
    switch (removeInputFromInvocation, removeSwiftDepsFile, afterRestoringBadPriors) {
    case
      (false, false, false),
      (false, true,  false),
      (false, false, true ),
      (true,  false, true ),
      (true,  true,  true ),
      (false, true,  true ):
      expectations = [
        .readGraphAndSkipAll(inputs)
      ]
    case
      (true, false, false),
      (true, true,  false):
      expectations = [
        .createdGraphFromSwiftdeps,
        .enablingCrossModule,
        .skippingAll(inputs),
      ]
    }

    let graph = try doABuild(
      "restoring incrementality after removal of \(removedInput)",
      checkDiagnostics: true,
      extraArguments: extraArguments,
      expecting: expectations,
      whenAutolinking: autolinkLifecycleExpectations)
      .moduleDependencyGraph()

    graph.verifyGraph()
    if removeInputFromInvocation {
      if afterRestoringBadPriors {
        // FIXME: Fix the driver
        // If you incrementally compile with a.swift and b.swift,
        // at the end, the driver saves a serialized `ModuleDependencyGraph`
        // contains nodes for declarations defined in both files.
        // If you then later remove b.swift and recompile, the driver will
        // see that a file was removed (via comparisons with the saved `BuildRecord`
        // and will delete the saved priors. However, if for some reason the
        // saved priors are not deleted, the driver will read saved priors
        // containing entries for the deleted file. This test simulates that
        // condition by restoring the deleted priors. The driver ought to be fixed
        // to cull any entries for removed files from the deserialized priors.
        print("*** WARNING: skipping checks, driver fails to cleaned out the graph ***",
              to: &stderrStream); stderrStream.flush()
        return graph
      }
      graph.ensureOmits(sourceBasenameWithoutExt: removedInput)
      graph.ensureOmits(name: topLevelName)
    }
    else {
      XCTAssert(graph.contains(sourceBasenameWithoutExt: removedInput))
      XCTAssert(graph.contains(name: topLevelName))
    }

    return graph
  }

  private func checkReactionToTouchingSymlinks(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) throws {
    for (file, _) in self.inputPathsAndContents {
      try localFileSystem.removeFileTree(file)
      let linkTarget = tempDir.appending(component: "links").appending(component: file.basename)
      try localFileSystem.createSymbolicLink(file, pointingAt: linkTarget, relative: false)
    }
    try doABuild(
      "touch both symlinks; non-propagating",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expecting: [
        .enablingCrossModule,
        .readGraph,
        .maySkip("main", "other"),
        .skipping("main", "other"),
        .skippingLinking,
        .skipped("main", "other"),
      ],
      whenAutolinking: autolinkLifecycleExpectations)
  }

  private func checkReactionToTouchingSymlinkTargets(
    checkDiagnostics: Bool = false,
    extraArguments: [String] = []
  ) throws {
    for (file, contents) in self.inputPathsAndContents {
      let linkTarget = tempDir.appending(component: "links").appending(component: file.basename)
      try! localFileSystem.writeFileContents(linkTarget) { $0 <<< contents }
    }
    try doABuild(
      "touch both symlink targets; non-propagating",
      checkDiagnostics: checkDiagnostics,
      extraArguments: extraArguments,
      expecting: [
        .enablingCrossModule,
        .readGraph,
        .schedulingChanged("main", "other"),
        .queuingInitial("main", "other"),
        .notSchedulingDependentsUnknownChanges("main", "other"),
        .findingBatchingCompiling("main", "other"),
        .schedulingPostCompileJobs,
        .linking,
      ],
      whenAutolinking: autolinkLifecycleExpectations)
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
    // Written this way to show the faulty node when the assertion fails
    nodeFinder.forEachNode { node in
      XCTAssertFalse(node.contains(sourceBasenameWithoutExt: target),
                     "graph should omit source: \(target)")
    }
  }
  func ensureOmits(name: String) {
    // Written this way to show the faulty node when the assertion fails
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
  fileprivate func doABuild(_ message: String,
                checkDiagnostics: Bool,
                extraArguments: [String],
                expecting expectations: [[Diagnostic.Message]],
                whenAutolinking autolinkExpectations: [Diagnostic.Message]
  ) throws -> Driver {
    print("*** starting build \(message) ***", to: &stderrStream); stderrStream.flush()

    guard let sdkArgumentsForTesting = try Driver.sdkArgumentsForTesting()
    else {
      throw XCTSkip("Cannot perform this test on this host")
    }
    let allArgs = commonArgs + extraArguments + sdkArgumentsForTesting

    return try checkDiagnostics
    ? doABuild(expecting: expectations,
               whenAutolinking: autolinkExpectations,
               arguments: allArgs)
    : doABuildWithoutExpectations(arguments: allArgs)
  }

  private func doABuild(
    expecting expectations: [[Diagnostic.Message]],
    whenAutolinking autolinkExpectations: [Diagnostic.Message],
    arguments: [String]
  ) throws -> Driver {
    try assertDriverDiagnostics(args: arguments) {
      driver, verifier in
      verifier.forbidUnexpected(.error, .warning, .note, .remark, .ignored)
      expectations.forEach {$0.forEach {verifier.expect($0)}}
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

// MARK: - Expectation (sequence) coding
fileprivate extension Array where Element == Diagnostic.Message {
  // MARK: - misc
  static func remarks(_ msgs: String...) -> Self {
    remarks(msgs)
  }
  static func remarks(_ msgs: [String]) -> Self {
    msgs.map(Element.remark)
  }
  /// Shorthand for a series of remarks depending on inputs
  static func remarks(about inputs: [String], _ stringFromInput: (String) -> String) -> Self {
    remarks(inputs.map(stringFromInput))
  }
  static let enablingCrossModule: Self =
    remarks("Incremental compilation: Enabling incremental cross-module building")

  // MARK: - build record
  static let cannotReadBuildRecord: Self =
    remarks("Incremental compilation: Incremental compilation could not read build record at")
  static let disablingIncrementalCannotReadBuildRecord: Self =
    remarks("Incremental compilation: Disabling incremental build: could not read build record")

  // MARK: - graph
  static let createdGraphFromSwiftdeps: Self =
    remarks("Incremental compilation: Created dependency graph from swiftdeps files")
  static let readGraph: Self =
    remarks("Incremental compilation: Read dependency graph")

  // MARK: - dependencies
  static func fingerprintChanged(_ aspect: DependencyKey.DeclAspect, _ input: String) -> Self {
    remarks("Incremental compilation: Fingerprint changed for \(aspect) of source file \(input).swiftdeps in \(input).swiftdeps")
  }
  static func newDefinitionOfSourceFile(_ aspect: DependencyKey.DeclAspect, _ input: String) -> Self {
    remarks("Incremental compilation: New definition: \(aspect) of source file \(input).swiftdeps in \(input).swiftdeps")
  }
  static func newDefinitionOfTopLevelName(_ aspect: DependencyKey.DeclAspect, name: String, input: String) -> Self {
    remarks("Incremental compilation: New definition: \(aspect) of top-level name '\(name)' in \(input).swiftdeps")
  }

  // MARK: - scheduling
  static func schedulingAlwaysRebuild(_ input: String) -> Self {
    remarks("Incremental compilation: scheduling dependents of \(input).swift; -driver-always-rebuild-dependents")
  }
  static func schedulingNew(_ input: String) -> Self {
    remarks("Incremental compilation: Scheduling new  {compile: \(input).o <= \(input).swift}")
  }
  static func schedulingChanged(_ inputs: String...) -> Self {
    remarks(about: inputs) {input in
      "Incremental compilation: Scheduing changed input  {compile: \(input).o <= \(input).swift}"}
  }
  static func notSchedulingDependentsNoEntry(_ input: String) -> Self {
    remarks("Incremental compilation: not scheduling dependents of \(input).swift: no entry in build record or dependency graph")
  }
  static func notSchedulingDependentsUnknownChanges(_ inputs: String...) -> Self {
    remarks(about: inputs) {input in
      "Incremental compilation: not scheduling dependents of \(input).swift; unknown changes"
    }
  }
  static func queuingInitial(_ inputs: String...) -> Self {
    remarks(about: inputs) {input in
      "Incremental compilation: Queuing (initial):  {compile: \(input).o <= \(input).swift}"
    }
  }
  static func missing(_ input: String) -> Self {
    remarks("Incremental compilation: Missing an output; will queue  {compile: \(input).o <= \(input).swift}")
  }

// MARK: - skipping
  static func maySkip(_ inputs: [String]) -> Self {
    remarks(about: inputs) {input in
      "Incremental compilation: May skip current input:  {compile: \(input).o <= \(input).swift}"
    }
  }
  static func maySkip(_ inputs: String...) -> Self {
    maySkip(inputs)
  }
 static func skipping(_ inputs: [String]) -> Self {
   remarks(about: inputs) {input in
     "Incremental compilation: Skipping input:  {compile: \(input).o <= \(input).swift}"
   }
 }
  static func skipping(_ inputs: String...) -> Self {
    skipping(inputs)
  }
 static func skipped(_ inputs: [String]) -> Self {
   remarks(about: inputs) {input in
   "Skipped Compiling \(input).swift"
   }
 }
  static func skipped(_ inputs: String...) -> Self {
    skipped(inputs)
  }
  static func skippingAll(_ inputs: [String]) -> Self {
     [
      maySkip(inputs), skipping(inputs), skippingLinking, skipped(inputs)
     ].flatMap {$0}
   }
  static func skippingAll(_ inputs: String...) -> Self {
     skippingAll(inputs)
   }
  static func readGraphAndSkipAll(_ inputs: [String]) -> Self {
    [
      readGraph,
      enablingCrossModule,
      skippingAll(inputs)
    ].flatMap{$0}
  }
  static func readGraphAndSkipAll(_ inputs: String...) -> Self {
    readGraphAndSkipAll(inputs)
  }

// MARK: - batching
  static func addingToBatch(_ inputs: [String], _ b: Int) -> Self {
    remarks(about: inputs) {input in
      "Adding {compile: \(input).swift} to batch \(b)"
    }
  }
  static func formingBatch(_ inputs: [String]) -> Self {
      remarks("Forming batch job from \(inputs.count) constituents: \(inputs.map{$0 + ".swift"}.joined(separator: ", "))")
  }
  static func foundBatchableJobs(_ jobCount: Int) -> Self {
    // Omitting the "s" from "jobs" works for either 1 or many, since
    // the verifier does prefix matching.
    remarks("Found \(jobCount) batchable job")
  }
  static let formingOneBatch: Self = remarks("Forming into 1 batch")

  static func findingAndFormingBatch(_ jobCount: Int) -> Self {
    [foundBatchableJobs(jobCount), formingOneBatch].flatMap{$0}
  }
  static func addingToBatchThenForming(_ inputs: [String]) -> Self {
    [addingToBatch(inputs, 0), formingBatch(inputs)].flatMap{$0}
  }
  static func addingToBatchThenForming(_ inputs: String...) -> Self {
    addingToBatchThenForming(inputs)
  }

  // MARK: - compiling
  static func starting(_ inputs: [String]) -> Self {
    remarks("Starting Compiling \(inputs.map{$0 + ".swift"}.joined(separator: ", "))")
  }
  static func finished(_ inputs: [String]) -> Self {
    remarks("Finished Compiling \(inputs.map{$0 + ".swift"}.joined(separator: ", "))")
  }
  static func compiling(_ inputs: [String]) -> Self {
    [starting(inputs), finished(inputs)].flatMap{$0}
  }
  static func compiling(_ inputs: String...) -> Self {
    compiling(inputs)
  }

// MARK: - batching and compiling
  static func findingBatchingCompiling(_ inputs: String...) -> Self {
    [
      findingAndFormingBatch(inputs.count),
      addingToBatchThenForming(inputs),
      compiling(inputs)
    ].flatMap {$0}
  }

  // MARK: - linking
  static let schedulingPostCompileJobs: Self =
  remarks("Incremental compilation: Scheduling all post-compile jobs because something was compiled")

  static let startingLinking: Self = remarks("Starting Linking theModule")

  static let finishedLinking: Self = remarks("Finished Linking theModule")

  static let skippingLinking: Self =
    remarks("Incremental compilation: Skipping job: Linking theModule; oldest output is current")

  static let schedLinking: Self = [schedulingPostCompileJobs, linking].flatMap{$0}

  static let linking: Self = [startingLinking + finishedLinking].flatMap{$0}

  // MARK: - autolinking
  static func queuingExtractingAutolink(_ module: String) -> Self {
      remarks("Incremental compilation: Queuing Extracting autolink information for module \(module)")
  }
  static func startingExtractingAutolink(_ module: String) -> Self {
      remarks("Starting Extracting autolink information for module \(module)")
  }
  static func finishedExtractingAutolink(_ module: String) -> Self {
      remarks("Finished Extracting autolink information for module \(module)")
  }
  static func extractingAutolink(_ module: String) -> Self {
    [startingExtractingAutolink(module), finishedExtractingAutolink(module)].flatMap{$0}
  }
}
