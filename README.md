# Swift compiler driver

A reimplementation of the Swift compiler's "driver", which coordinates Swift compilation,
linking, etc., in Swift. Why reimplement the Swift compiler driver?

* Swift is way more fun to code in than C++
* Swift's current driver code is a bit messy and could use major refactoring
* Swift's driver is standalone, relatively small (~10kloc) and in a separate process from the main body of the compiler, so it's an easy target for reimplementation

# TODO

The driver currently does very little. Next steps:

* Implement parsing of command line arguments (e.g., the `[String]` produced by `CommandLine.arguments`) into an array of `Option` instances, capturing arguments and diagnosing unrecognized options, missing arguments, and other user errors.
* Infer the driver mode/kind from the name of the binary (e.g., `swift` -> `DriverKind.interactive`, `swiftc` -> `DriverKind.batch`, etc.) so we get the right options table. Recognize `--driver-mode` to change the mode from the command line.
* Start building abstractions for inputs, outputs, and jobs.
