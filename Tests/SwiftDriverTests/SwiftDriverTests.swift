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
      XCTAssertEqual(driver1.compilerMode, .immediate)

      let driver2 = try Driver(args: ["swift"])
      XCTAssertEqual(driver2.compilerMode, .repl)
    }

    do {
      let driver1 = try Driver(args: ["swiftc", "main.swift", "-whole-module-optimization"])
      XCTAssertEqual(driver1.compilerMode, .singleCompile)

      let driver2 = try Driver(args: ["swiftc", "main.swift", "-g"])
      XCTAssertEqual(driver2.compilerMode, .standardCompile)
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

  func testDebugSettings() throws {
    let driver1 = try Driver(args: ["swiftc", "foo.swift", "-emit-module"])
    XCTAssertNil(driver1.debugInfoLevel)
    XCTAssertEqual(driver1.debugInfoFormat, .dwarf)

    let driver2 = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-g"])
    XCTAssertEqual(driver2.debugInfoLevel, .astTypes)
    XCTAssertEqual(driver2.debugInfoFormat, .dwarf)

    let driver3 = try Driver(args: ["swiftc", "-g", "foo.swift", "-gline-tables-only"])
    XCTAssertEqual(driver3.debugInfoLevel, .lineTables)
    XCTAssertEqual(driver3.debugInfoFormat, .dwarf)

    let driver4 = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=codeview"])
    XCTAssertEqual(driver4.debugInfoLevel, .astTypes)
    XCTAssertEqual(driver4.debugInfoFormat, .codeView)

    let driver5 = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-debug-info-format=dwarf"])
    XCTAssertEqual(driver5.diagnosticEngine.diagnostics.map{$0.localizedDescription}, ["option '-debug-info-format=' is missing a required argument (-g)"])

    let driver6 = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-g", "-debug-info-format=notdwarf"])
    XCTAssertEqual(driver6.diagnosticEngine.diagnostics.map{$0.localizedDescription}, ["invalid value 'notdwarf' in '-debug-info-format='"])

    let driver7 = try Driver(args: ["swiftc", "foo.swift", "-emit-module", "-gdwarf-types", "-debug-info-format=codeview"])
    XCTAssertEqual(driver7.diagnosticEngine.diagnostics.map{$0.localizedDescription}, ["argument 'codeview' is not allowed with '-gdwarf-types'"])
  }

  func testModuleSettings() throws {
    let driver1 = try Driver(args: ["swiftc", "foo.swift"])
    XCTAssertNil(driver1.moduleOutputKind)
    XCTAssertEqual(driver1.moduleName, "foo")

    let driver2 = try Driver(args: ["swiftc", "foo.swift", "-g"])
    XCTAssertEqual(driver2.moduleOutputKind, .auxiliary)
    XCTAssertEqual(driver2.moduleName, "foo")

    let driver3 = try Driver(args: ["swiftc", "foo.swift", "-module-name", "wibble", "bar.swift", "-g"])
    XCTAssertEqual(driver3.moduleOutputKind, .auxiliary)
    XCTAssertEqual(driver3.moduleName, "wibble")

    let driver4 = try Driver(args: ["swiftc", "-emit-module", "foo.swift", "-module-name", "wibble", "bar.swift"])
    XCTAssertEqual(driver4.moduleOutputKind, .topLevel)
    XCTAssertEqual(driver4.moduleName, "wibble")

    let driver5 = try Driver(args: ["swiftc", "foo.swift", "bar.swift"])
    XCTAssertNil(driver5.moduleOutputKind)
    XCTAssertEqual(driver5.moduleName, "main")

    let driver6 = try Driver(args: ["swiftc", "-repl"])
    XCTAssertNil(driver6.moduleOutputKind)
    XCTAssertEqual(driver6.moduleName, "REPL")

    let driver7 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-emit-library", "-o", "libWibble.so"])
    XCTAssertEqual(driver7.moduleName, "Wibble")

    let driver8 = try Driver(args: ["swiftc", "foo.swift", "bar.swift", "-emit-library", "-o", "libWibble.so", "-module-name", "Swift"])
    XCTAssertEqual(driver8.diagnosticEngine.diagnostics.map{$0.localizedDescription}, ["module name \"Swift\" is reserved for the standard library"])
  }
}
