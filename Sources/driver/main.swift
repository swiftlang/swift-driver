import SwiftDriver
import TSCLibc

do {
  let driver = try Driver(args: CommandLine.arguments)
  driver.run()
} catch {
  print("error: \(error)")
  exit(EXIT_FAILURE)
}
