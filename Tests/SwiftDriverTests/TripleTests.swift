import XCTest

import SwiftDriver
import TSCBasic

final class TripleTests: XCTestCase {
  func testBasics() throws {
    XCTAssertEqual(Triple("").arch, .unknown)
    XCTAssertEqual(Triple("kalimba").arch, .kalimba)
    XCTAssertEqual(Triple("x86_64-apple-macosx").arch, .x86_64)
    XCTAssertEqual(Triple("blah-apple").arch, .unknown)

    XCTAssertEqual(Triple("x86_64-apple-macosx").vendor, .apple)
    XCTAssertEqual(Triple("x86_64-apple-macosx").os, .macosx)
  }
}
