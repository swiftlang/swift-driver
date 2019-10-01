import SwiftDriver
import TSCLibc

do {
  var driver = try Driver(args: CommandLine.arguments)
  try driver.run()

  if driver.diagnosticEngine.hasErrors {
    exit(EXIT_FAILURE)
  }
} catch {
  print("error: \(error)")
  exit(EXIT_FAILURE)
}
