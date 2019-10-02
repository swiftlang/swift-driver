import SwiftDriver
import TSCLibc

do {
  var driver = try Driver(args: CommandLine.arguments)
  let resolver = try ArgsResolver()
  try driver.run(resolver: resolver)

  if driver.diagnosticEngine.hasErrors {
    exit(EXIT_FAILURE)
  }
} catch {
  print("error: \(error)")
  exit(EXIT_FAILURE)
}
