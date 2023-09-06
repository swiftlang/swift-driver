// Created by David Ungar on 7/28/21.
//

import XCTest
@_spi(Testing) import SwiftDriver
import TSCBasic

class IncrementalBuildPerformanceTests: XCTestCase {
  enum WhatToMeasure { case readingSwiftDeps, writing, readingPriors }

  /// Test the cost of reading `swiftdeps` files without doing a full build. Use the files in "TestInputs/SampleSwiftDeps"
  ///
  /// When doing an incremental but clean build, after every file is compiled, its `swiftdeps` file must be
  /// deserialized and integrated into the `ModuleDependencyGraph`.
  /// This test allows us to profile an optimize this work. (Set up the scheme to run optimized code.)
  /// It reads and integrages every swiftdeps file in a given directory.
  ///
  /// This test relies on sample `swiftdeps` files to be present in `<project-folder>/TestInputs/SampleSwiftDeps`.
  /// If the serialization format changes, they will need to be regenerated.
  /// To regenerate them:
  /// `cd` to the package directory, then:
  /// `rm TestInputs/SampleSwiftDeps/*; rm -rf .build; swift build; find .build -name \*.swiftdeps -a -exec cp \{\} TestInputs/SampleSwiftDeps \;`
  func testCleanBuildSwiftDepsPerformance() throws {
    try testPerformance(.readingSwiftDeps)
  }
  func testSavingPriorsPerformance() throws {
    try testPerformance(.writing)
  }
  func testReadingPriorsPerformance() throws {
    try testPerformance(.readingPriors)
  }


  func testPerformance(_ whatToMeasure: WhatToMeasure) throws {

#if !os(macOS)
      // rdar://81411914
      throw XCTSkip()
#else

    let packageRootPath = try AbsolutePath(validating: #file)
      .parentDirectory
      .parentDirectory
      .parentDirectory
    let swiftDepsDirectoryPath = packageRootPath.appending(components: "TestInputs", "SampleSwiftDeps")

    #if DEBUG
    let limit = 5 // Just a few times to be sure it works
    #else
    let limit = 100 // This is the real test, optimized code.
    #endif

    try test(swiftDepsDirectory: swiftDepsDirectoryPath.pathString, atMost: limit, whatToMeasure)
#endif
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
  func test(swiftDepsDirectory: String, atMost limit: Int = .max, _ whatToMeasure: WhatToMeasure) throws {
    let (outputFileMap, inputs) = try createOFMAndInputs(swiftDepsDirectory, atMost: limit)

    let info = IncrementalCompilationState.IncrementalDependencyAndInputSetup
      .mock(options: [], outputFileMap: outputFileMap)

    let g = ModuleDependencyGraph.createForSimulatingCleanBuild(info.buildRecordInfo.buildRecord([], []), info)
    g.blockingConcurrentAccessOrMutation {
      switch whatToMeasure {
      case .readingSwiftDeps:
        measure {readSwiftDeps(for: inputs, into: g)}
      case .writing:
        readSwiftDeps(for: inputs, into: g)
        measure {
          _ = ModuleDependencyGraph.Serializer.serialize(
            g,
            g.buildRecord,
            ModuleDependencyGraph.serializedGraphVersion)
        }
      case .readingPriors:
        readSwiftDeps(for: inputs, into: g)
        let data = ModuleDependencyGraph.Serializer.serialize(
          g,
          g.buildRecord,
          ModuleDependencyGraph.serializedGraphVersion)
        measure {
          try? XCTAssertNoThrow(ModuleDependencyGraph.deserialize(data, info: info))
        }
      }
    }
  }

  /// Build the `OutputFileMap` and input vector for ``testCleanBuildSwiftDepsPerformance(_, atMost)``
  private func createOFMAndInputs(_ swiftDepsDirectory: String,
                                  atMost limit: Int
  ) throws -> (OutputFileMap, [SwiftSourceFile]) {
    let workingDirectory = localFileSystem.currentWorkingDirectory!
    let swiftDepsDirPath = try VirtualPath.init(path: swiftDepsDirectory).resolvedRelativePath(base: workingDirectory).absolutePath!
    let withoutExtensions: ArraySlice<Substring> = try localFileSystem.getDirectoryContents(swiftDepsDirPath)
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
    let inputs = withoutExtensions.map {mkPath($0, .swift)}.swiftSourceFiles
    let swiftDepsVPs = withoutExtensions.map {mkPath($0, .swiftDeps)}
    let entries = Dictionary(
      uniqueKeysWithValues:
        zip(inputs, swiftDepsVPs).map {input, swiftDeps in
          (input.fileHandle, [swiftDeps.type: swiftDeps.fileHandle])
        })
    return (OutputFileMap(entries: entries), inputs)
  }

  /// Read the `swiftdeps` files for each input into a `ModuleDependencyGraph`
  private func readSwiftDeps(for inputs: [SwiftSourceFile], into g: ModuleDependencyGraph) {
    let result = inputs.reduce(into: Set()) { invalidatedInputs, primaryInput in
      // too verbose: print("processing", primaryInput)
      invalidatedInputs.formUnion(g.collectInputsRequiringCompilation(byCompiling: primaryInput)!)
    }
    .subtracting(inputs) // have already compiled these

    XCTAssertEqual(result.count, 0, "Should be no invalid inputs left")
  }
}
