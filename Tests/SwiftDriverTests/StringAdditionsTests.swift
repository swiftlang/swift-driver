import XCTest
@testable import SwiftDriver

class StringAdditionsTests: XCTestCase {
  func testInterpolationOr() {
    let one: Int? = 1
    let none: Int? = nil

    XCTAssertEqual("\(one, or: "nope")", "1")
    XCTAssertEqual("\(none, or: "nope")", "nope")
  }
}
