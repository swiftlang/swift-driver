import SwiftDriver
import TSCLibc

do {
  var driver = try Driver(args: CommandLine.arguments)
  try driver.run()
} catch {
  print("error: \(error)")
  exit(EXIT_FAILURE)
}
