import XCTest

import SwiftDriver

final class SwiftDriverTests: XCTestCase {
    func testParsing() throws {
      // Form a simple options table
      var options = OptionTable()
      options.addOption(spelling: "", generator: .input)
      options.addOption(
        spelling: "-color-diagnostics", generator: .flag({.color_diagnostics}))
      options.addOption(spelling: "-I",
                        generator: .joinedOrSeparate {
                          path in Option.I(path)
        })
      options.addAlias(spelling: "-I=", generator: .joined {
        path in Option.I(path)
        })
      options.addAlias(spelling: "-module-name",
                       generator: .separate {
                        name in Option.module_name(name)
      })
      options.addOption(spelling: "-sanitize=",
                        generator: .commaJoined {
                          args in Option.sanitize_EQ(args)
      })
      options.addOption(spelling: "--",
                        generator: .remaining(Option._DASH_DASH))

      // Parse each kind of option
      let results = try options.parse([
        "input1", "-color-diagnostics", "-Ifoo", "-I", "bar",
        "-I=wibble", "input2", "-module-name", "main",
        "-sanitize=a,b,c", "--", "-foo", "-bar"])
      XCTAssertEqual(results,
                     [Option.INPUT("input1"),
                      Option.color_diagnostics,
                      Option.I("foo"),
                      Option.I("bar"),
                      Option.I("wibble"),
                      Option.INPUT("input2"),
                      Option.module_name("main"),
                      Option.sanitize_EQ(["a", "b", "c"]),
                      Option._DASH_DASH(["-foo", "-bar"])])
    }

  func testParseErrors() {
    var options = OptionTable()
    options.addOption(spelling: "", generator: .input)
    options.addOption(
      spelling: "-color-diagnostics", generator: .flag({.color_diagnostics}))
    options.addOption(spelling: "-I",
                      generator: .joinedOrSeparate {
                        path in Option.I(path)
      })
    options.addAlias(spelling: "-I=", generator: .joined {
      path in Option.I(path)
      })
    options.addAlias(spelling: "-module-name",
                     generator: .separate {
                      name in Option.module_name(name)
    })
    options.addOption(spelling: "-sanitize=",
                      generator: .commaJoined {
                        args in Option.sanitize_EQ(args)
    })
    options.addOption(spelling: "--",
                      generator: .remaining(Option._DASH_DASH))

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
      let driver = try Driver(args: ["swift"])
      XCTAssertEqual(driver.computeCompilerMode(options: [.INPUT("main.swift")]), .immediate)
      XCTAssertEqual(driver.computeCompilerMode(options: []), .repl)
    }

    do {
      let driver = try Driver(args: ["swiftc"])
      XCTAssertEqual(driver.computeCompilerMode(options: [.INPUT("main.swift"), .whole_module_optimization]), .singleCompile)
      XCTAssertEqual(driver.computeCompilerMode(options: [.INPUT("main.swift"), .g]), .standardCompile)
    }
  }
}
