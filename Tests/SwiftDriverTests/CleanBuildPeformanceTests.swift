// Created by David Ungar on 7/28/21.
// 

import XCTest
@_spi(Testing) import SwiftDriver
import TSCBasic
import TSCUtility

class CleanBuildPeformanceTests: XCTestCase {
  /// Test the cost of reading `swiftdeps` files without doing a full build. Use the files in "TestInputs/SampleSwiftDeps"
  ///
  /// When doing an incremental but clean build, after every file is compiled, its `swiftdeps` file must be
  /// deserialized and integrated into the `ModuleDependencyGraph`.
  /// This test allows us to profile an optimize this work. (Set up the scheme to run optimized code.)
  /// It reads and integrages every swiftdeps file in a given directory.
  func testCleanBuildSwiftDepsPerformance() throws {
    let packageRootPath = AbsolutePath(#file)
      .parentDirectory
      .parentDirectory
      .parentDirectory
    let swiftDepsDirectoryPath = packageRootPath.appending(components: "TestInputs", "SampleSwiftDeps")

    #if DEBUG
    let limit = 5 // Just a few times to be sure it works
    #else
    let limit = 100 // This is the real test, optimized code.
    #endif

    try test(swiftDepsDirectory: swiftDepsDirectoryPath.pathString, atMost: limit)
  }

  /// Test the cost of reading `swiftdeps` files without doing a full build.
  ///
  /// When doing an incremental but clean build, after every file is compiled, its `swiftdeps` file must be
  /// deserialized and integrated into the `ModuleDependencyGraph`.
  /// This test allows us to profile an optimize this work. (Set up the scheme to run optimized code.)
  /// It reads and integrages every swiftdeps file in a given directory.
  /// - Parameters:
  ///    - swiftDepsDirectory: where the swiftdeps files are, either absolute, or relative to the current directory
  ///    - limit: the maximum number of swiftdeps files to process.
  func test(swiftDepsDirectory: String, atMost limit: Int = .max) throws {
    let (outputFileMap, inputs) = try createOFMAndInputs(swiftDepsDirectory, atMost: limit)

    let info = IncrementalCompilationState.IncrementalDependencyAndInputSetup
      .mock(options: [], outputFileMap: outputFileMap)
    let g = ModuleDependencyGraph(info, .updatingAfterCompilation)
    measure {readSwiftDeps(for: inputs, into: g)}
  }

  /// Build the `OutputFileMap` and input vector for ``testCleanBuildSwiftDepsPeformance(_, atMost)``
  private func createOFMAndInputs(_ swiftDepsDirectory: String,
                                  atMost limit: Int
  ) throws -> (OutputFileMap, [TypedVirtualPath]) {
    let workingDirectory = localFileSystem.currentWorkingDirectory!
    let swiftDepsDirPath = try VirtualPath.init(path: swiftDepsDirectory).resolvedRelativePath(base: workingDirectory).absolutePath!
    let withoutExtensions: ArraySlice<Substring> = try! localFileSystem.getDirectoryContents(swiftDepsDirPath)
      .compactMap {
        fileName -> Substring? in
        guard let suffixRange = fileName.range(of: ".swiftdeps"),
              suffixRange.upperBound == fileName.endIndex
        else {
          return nil
        }
        let withoutExtension = fileName.prefix(upTo: suffixRange.lowerBound)
        guard !withoutExtension.hasSuffix("-master") else { return nil }
        return withoutExtension
      }
      .sorted()
      .prefix(limit)
    print("reading", withoutExtensions.count, "swiftdeps files")
    func mkPath( _ name: Substring, _ type: FileType) -> TypedVirtualPath {
      TypedVirtualPath(
        file: VirtualPath.absolute(swiftDepsDirPath.appending(component: name + "." + type.rawValue)).intern(),
        type: type)
    }
    let inputs = withoutExtensions.map {mkPath($0, .swift)}
    let swiftDepsVPs = withoutExtensions.map {mkPath($0, .swiftDeps)}
    let entries = Dictionary(
      uniqueKeysWithValues:
        zip(inputs, swiftDepsVPs).map {input, swiftDeps in
          (input.fileHandle, [swiftDeps.type: swiftDeps.fileHandle])
        })
    return (OutputFileMap(entries: entries), inputs)
  }

  /// Read the `swiftdeps` files for each input into a `ModuleDependencyGraph`
  private func readSwiftDeps(for inputs: [TypedVirtualPath], into g: ModuleDependencyGraph) {
    let result = inputs.reduce(into: Set()) { invalidatedInputs, primaryInput in
      // too verbose: print("processing", primaryInput)
      invalidatedInputs.formUnion(g.collectInputsRequiringCompilation(byCompiling: primaryInput)!)
    }
    .subtracting(inputs) // have already compiled these

    XCTAssertEqual(result.count, 0, "Should be no invalid inputs left")
  }
}
