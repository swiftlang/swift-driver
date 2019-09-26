# Swift compiler driver

A reimplementation of the Swift compiler's "driver", which coordinates Swift compilation,
linking, etc., in Swift. Why reimplement the Swift compiler driver?

* Swift is way more fun to code in than C++
* Swift's current driver code is a bit messy and could use major refactoring
* Swift's driver is standalone, relatively small (~10kloc) and in a separate process from the main body of the compiler, so it's an easy target for reimplementation

## Building

Use the Swift package manager to build.

```
$ swift build
```

If you need to run the `makeOptions`
utility, make sure to build with a `-I` which allows the Swift `Options.inc` to
be found.

```
$ swift build -Xcc -I/path/to/build/Ninja-ReleaseAssert/swift-.../include
```

# TODO

The driver currently does very little. Next steps:

* [ ] Implement parsing of command line arguments (e.g., the `[String]` produced by `CommandLine.arguments`) into an array of `Option` values, capturing arguments and diagnosing unrecognized options, missing arguments, and other user errors.
* [ ] Infer the driver mode/kind from the name of the binary (e.g., `swift` -> `DriverKind.interactive`, `swiftc` -> `DriverKind.batch`, etc.) so we get the right options table. Recognize `--driver-mode` to change the mode from the command line.
* [ ] Start building abstractions for inputs, outputs, and jobs.
* [ ] Write a little script to help automate the compilation of that horrible C++ program `makeOptions.cpp` (passing in the Swift build directory so it can find the generated `Options.inc`) so we can automatically update `Options.swift`. Is there any way to do this via `Package.swift` to make it automatic?
* [ ] Reflect option "group" information from `Options.inc` in the generated `Option`, since we'll need group-based queries.
* [ ] Figure out a principled way to walk an array of `Option` values and turn it into command lines for various jobs so that we don't "forget" to process a particular kind of option.
