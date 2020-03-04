import XCTest

import SwiftDriverTests
import SwiftOptionsTests

var tests = [XCTestCaseEntry]()
tests += SwiftDriverTests.__allTests()
tests += SwiftOptionsTests.__allTests()

XCTMain(tests)
