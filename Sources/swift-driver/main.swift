import SwiftDriver
import TSCLibc

do {
  let toolchain = DarwinToolchain()
  var driver = try Driver(args: CommandLine.arguments)
  let resolver = try ArgsResolver(toolchain: toolchain)
  try driver.run(resolver: resolver)

  if driver.diagnosticEngine.hasErrors {
    exit(EXIT_FAILURE)
  }
} catch {
  print("error: \(error)")
  exit(EXIT_FAILURE)
}
