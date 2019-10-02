import SwiftDriver
import TSCLibc
import enum TSCUtility.Diagnostics

do {
  var driver = try Driver(args: CommandLine.arguments)
  let resolver = try ArgsResolver()
  try driver.run(resolver: resolver)

  if driver.diagnosticEngine.hasErrors {
    exit(EXIT_FAILURE)
  }
} catch Diagnostics.fatalError {
  exit(EXIT_FAILURE)
} catch {
  print("error: \(error)")
  exit(EXIT_FAILURE)
}
