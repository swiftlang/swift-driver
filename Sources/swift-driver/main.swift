import SwiftDriver

import TSCLibc
import TSCBasic
import TSCUtility

var intHandler: InterruptHandler?

do {
  let processSet = ProcessSet()
  intHandler = try InterruptHandler {
    processSet.terminate()
  }

  var driver = try Driver(args: CommandLine.arguments)
  let resolver = try ArgsResolver()
  try driver.run(resolver: resolver, processSet: processSet)

  if driver.diagnosticEngine.hasErrors {
    exit(EXIT_FAILURE)
  }
} catch Diagnostics.fatalError {
  exit(EXIT_FAILURE)
} catch {
  print("error: \(error)")
  exit(EXIT_FAILURE)
}
