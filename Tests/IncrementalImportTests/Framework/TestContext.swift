// Created by David Ungar on 3/5/21.
// 
import TSCBasic

struct TestContext: CustomStringConvertible {
  let testDir: AbsolutePath
  let withIncrementalImports: Bool
  let testFile: StaticString
  let testLine: UInt

  init(in testDir: AbsolutePath,
       withIncrementalImports: Bool,
       testFile: StaticString,
       testLine: UInt) {
    self.testDir = testDir
    self.withIncrementalImports = withIncrementalImports
    self.testFile = testFile
    self.testLine = testLine
  }

  var description: String {
    "\(testFile): \(testLine), \(withIncrementalImports ? "with" : "without") incremental imports"
  }
}
