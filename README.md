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
$ swift build -Xcc -I/path/to/build/Ninja-ReleaseAssert/swift-.../include --product makeOptions

```

## Testing

Test using command-line SwiftPM or Xcode.

```
$ swift test --parallel
```

Integration tests are costly to run and are disable by default. Enable them
using `SWIFT_DRIVER_ENABLE_INTEGRATION_TESTS` environment variable. In Xcode,
you can set this variable in the scheme's test action.

```
$ SWIFT_DRIVER_ENABLE_INTEGRATION_TESTS=1 swift test --parallel
```

Some integration tests run the lit test suites in a Swift working copy.
To enable these, clone Swift and its dependencies and buld them with
build-script, then set both `SWIFT_DRIVER_ENABLE_INTEGRATION_TESTS`
and `SWIFT_DRIVER_LIT_DIR`, either in your Xcode scheme or
on the command line:

```
$ SWIFT_DRIVER_ENABLE_INTEGRATION_TESTS=1 \
  SWIFT_DRIVER_LIT_DIR=/path/to/build/Ninja-ReleaseAssert/swift-.../test-... \
  swift test --parallel
```

## Using with SwiftPM

Create a symlink of the `swift-driver` binary called `swiftc` and export that
path in `SWIFT_EXEC` variable. This will allow you to use the driver when
building and linking with SwiftPM. Manifest parsing will still be done using the
current driver. Example:

```
ln -s /path/to/built/swift-driver swiftc
SWIFT_EXEC=$PWD/swiftc swift build
```

# TODO

The driver has basic support for building and linking Swift code. There are a bunch of things that need doing!

* General
  * [ ] Search for `FIXME:` or `TODO:`: there are lots of little things to improve
  * [ ] Improve documentation of how to incorporate the driver into your own builds
  * [ ] Make it easier to drop-in `swift-driver` as a replacement for Swift
  * [ ] Add useful descriptions to any `Error` thrown within the library
* Option parsing
  * [ ] Look for complete "coverage" of the options in `Options.swift`. Is every option there checked somewhere in the driver?
  * [ ] Find a better way to describe aliases for options. Can they be of some other type `OptionAlias` so we can't make the mistake of (e.g.) asking for an alias option when we're translating options?
  * [ ] Diagnose unused options
  * [ ] Typo correction for misspelled option names
  * [ ] Find a better way than `makeOptions.cpp` to translate the command-line options from [Swift's repository](https://github.com/apple/swift/tree/master/include/swift/Option) into `Options.swift`.
* Platform support
  * [x] Teach the `DarwinToolchain` to also handle iOS, tvOS, watchOS
  * [x] Fill out the `GenericUnixToolchain` toolchain to get it working
  * [ ] Implement a `WindowsToolchain`
  * [ ] Implement proper tokenization for response files
* Compilation modes
  * [x] Batch mode
  * [ ] Whole-module-optimization mode
  * [ ] REPL and immediate modes
* Unimplemented features
  * [ ] Precompiled bridging headers
  * [ ] Support embedding of bitcode
  * [ ] Incremental compilation
  * [x] Parseable output, as used by SwiftPM
  * [x] Response files
  * [ ] Input and primary input file lists
* Testing
  * [ ] Build stuff with SwiftPM or xcodebuild or your favorite build system, using `swift-driver`.
  * [x] Shim in `swift-driver` so it can run the Swift repository's [driver test suite](https://github.com/apple/swift/tree/master/test/Driver)
  * [ ] Port interesting tests from the Swift repository's [driver test suite](https://github.com/apple/swift/tree/master/test/Driver) over to XCTest
* Fun experiments
  * [ ] Modify SwiftPM to import the SwiftDriver library, using its `Driver` to construct jobs and incorporate them into its own build graph
