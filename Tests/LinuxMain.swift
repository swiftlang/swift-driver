import XCTest

import driverTests

var tests = [XCTestCaseEntry]()
tests += driverTests.allTests()
XCTMain(tests)
