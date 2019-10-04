import XCTest
import Foundation
import TSCBasic

import SwiftDriver

final class ParsableMessageTests: XCTestCase {
  func testBeganMessage() throws {
    let msg = BeganMessage(
      pid: 1,
      inputs: ["/path/to/foo.swift"],
      outputs: [
      .init(path: "/path/to/foo.o", type: "object")
      ],
      commandExecutable: "/path/to/swiftc",
      commandArguments: ["-frontend", "compile"]
    )

    let beganMessage = ParsableMessage.beganMessage(name: "compile", msg: msg)

    let encoded = try beganMessage.toJSON()
    let string = String(data: encoded, encoding: .utf8)!

    XCTAssertEqual(string, """
      {
        "command_arguments" : [
          "-frontend",
          "compile"
        ],
        "command_executable" : "\\/path\\/to\\/swiftc",
        "inputs" : [
          "\\/path\\/to\\/foo.swift"
        ],
        "kind" : "began",
        "name" : "compile",
        "outputs" : [
          {
            "path" : "\\/path\\/to\\/foo.o",
            "type" : "object"
          }
        ],
        "pid" : 1
      }
      """)
  }

  func testFinishedMessage() throws {
    let msg = FinishedMessage(exitStatus: 1, pid: 1, output: "hello")
    let finishedMessage = ParsableMessage.finishedMessage(name: "compile", msg: msg)
    let encoded = try finishedMessage.toJSON()
    let string = String(data: encoded, encoding: .utf8)!

    XCTAssertEqual(string, """
    {
      "exit-status" : 1,
      "kind" : "finished",
      "name" : "compile",
      "output" : "hello",
      "pid" : 1
    }
    """)
  }
}
