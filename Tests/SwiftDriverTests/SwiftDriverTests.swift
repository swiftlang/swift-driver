import XCTest
import SwiftDriver
import TSCBasic

final class SwiftDriverTests: XCTestCase {
    func testParsing() throws {
      // Form an options table
      let options = OptionTable()
      // Parse each kind of option
      let results = try options.parse([
        "input1", "-color-diagnostics", "-Ifoo", "-I", "bar",
        "-I=wibble", "input2", "-module-name", "main",
        "-sanitize=a,b,c", "--", "-foo", "-bar"])
      XCTAssertEqual(results.description,
                     "input1 -color-diagnostics -I foo -I bar -I=wibble input2 -module-name main -sanitize=a,b,c -- -foo -bar")
    }

  func testParseErrors() {
    let options = OptionTable()

    // FIXME: Check for the exact form of the error
    XCTAssertThrowsError(try options.parse(["-unrecognized"]))
    XCTAssertThrowsError(try options.parse(["-I"]))
    XCTAssertThrowsError(try options.parse(["-module-name"]))
  }

  func testDriverKindParsing() throws {
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swift"]), .interactive)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["/path/to/swift"]), .interactive)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swiftc"]), .batch)
    XCTAssertEqual(try Driver.determineDriverKind(args: [".build/debug/swiftc"]), .batch)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swiftc", "-frontend"]), .frontend)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swiftc", "-modulewrap"]), .moduleWrap)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["/path/to/swiftc", "-modulewrap"]), .moduleWrap)

    XCTAssertEqual(try Driver.determineDriverKind(args: ["swiftc", "--driver-mode=swift"]), .interactive)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swiftc", "--driver-mode=swift-autolink-extract"]), .autolinkExtract)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swiftc", "--driver-mode=swift-indent"]), .indent)
    XCTAssertEqual(try Driver.determineDriverKind(args: ["swift", "--driver-mode=swift-autolink-extract"]), .autolinkExtract)

    XCTAssertThrowsError(try Driver.determineDriverKind(args: ["driver"]))
    XCTAssertThrowsError(try Driver.determineDriverKind(args: ["swiftc", "--driver-mode=blah"]))
    XCTAssertThrowsError(try Driver.determineDriverKind(args: ["swiftc", "--driver-mode="]))
  }

  func testCompilerMode() throws {
    do {
      let driver1 = try Driver(args: ["swift", "main.swift"])
      XCTAssertEqual(driver1.computeCompilerMode(), .immediate)

      let driver2 = try Driver(args: ["swift"])
      XCTAssertEqual(driver2.computeCompilerMode(), .repl)
    }

    do {
      let driver1 = try Driver(args: ["swiftc", "main.swift", "-whole-module-optimization"])
      XCTAssertEqual(driver1.computeCompilerMode(), .singleCompile)

      let driver2 = try Driver(args: ["swiftc", "main.swift", "-g"])
      XCTAssertEqual(driver2.computeCompilerMode(), .standardCompile)
    }
  }

  func testInputFiles() throws {
    let driver1 = try Driver(args: ["swift", "a.swift", "/tmp/b.swift"])
    XCTAssertEqual(driver1.inputFiles,
                   [ InputFile(file: .relative(RelativePath("a.swift")), type: .swift),
                     InputFile(file: .absolute(AbsolutePath("/tmp/b.swift")), type: .swift) ])
    let driver2 = try Driver(args: ["swift", "a.swift", "-working-directory", "/wobble", "/tmp/b.swift"])
    XCTAssertEqual(driver2.inputFiles,
                   [ InputFile(file: .absolute(AbsolutePath("/wobble/a.swift")), type: .swift),
                     InputFile(file: .absolute(AbsolutePath("/tmp/b.swift")), type: .swift) ])

    let driver3 = try Driver(args: ["swift", "-"])
    XCTAssertEqual(driver3.inputFiles, [ InputFile(file: .standardInput, type: .swift )])

    let driver4 = try Driver(args: ["swift", "-", "-working-directory" , "-wobble"])
    XCTAssertEqual(driver4.inputFiles, [ InputFile(file: .standardInput, type: .swift )])
  }

  func testPrimaryOutputKinds() throws {
    let driver1 = try Driver(args: ["swiftc", "foo.swift", "-emit-module"])
    XCTAssertEqual(driver1.compilerOutputType, .swiftModule)
    XCTAssertEqual(driver1.linkerOutputType, nil)

    let driver2 = try Driver(args: ["swiftc", "foo.swift", "-emit-library"])
    XCTAssertEqual(driver2.compilerOutputType, .object)
    XCTAssertEqual(driver2.linkerOutputType, .dynamicLibrary)

    let driver3 = try Driver(args: ["swiftc", "-static", "foo.swift", "-emit-library"])
    XCTAssertEqual(driver3.compilerOutputType, .object)
    XCTAssertEqual(driver3.linkerOutputType, .staticLibrary)
  }
}
