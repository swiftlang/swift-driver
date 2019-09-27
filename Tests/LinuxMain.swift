import XCTest

import libdriverTests

var tests = [XCTestCaseEntry]()
tests += libdriverTests.__allTests()

XCTMain(tests)
