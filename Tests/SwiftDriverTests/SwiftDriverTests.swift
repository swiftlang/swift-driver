import SwiftDriver
import XCTest

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
    XCTAssertThrowsError(try options.parse(["-unrecognized"]));
    XCTAssertThrowsError(try options.parse(["-I"]));
    XCTAssertThrowsError(try options.parse(["-module-name"]));
  }
}
