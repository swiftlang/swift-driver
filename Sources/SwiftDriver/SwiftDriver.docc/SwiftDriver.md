# ``SwiftDriver``

A native compiler driver for the Swift language.

## Overview

The `SwiftDriver` framework coordinates the compilation of Swift source code
into various compiled results: executables, libraries, object files, Swift
modules and interfaces, etc. It is the program one invokes from the command line
to build Swift code (i.e., swift or swiftc) and is often invoked on the
developer's behalf by a build system such as the
[Swift Package Manager](https://github.com/swiftlang/swift-package-manager)
or Xcode's build system.

## Topics

### Fundamentals

- <doc:SwiftDriver/Driver>
- <doc:SwiftDriver/DriverExecutor>

### Toolchains

- <doc:SwiftDriver/Toolchain>
- <doc:SwiftDriver/DarwinToolchain>
- <doc:SwiftDriver/GenericUnixToolchain>
- <doc:SwiftDriver/WebAssemblyToolchain>

### Incremental Builds

- <doc:SwiftDriver/IncrementalBuilds>

### Explicit Module Builds

- <doc:SwiftDriver/ExplicitModuleBuilds>

### Utilities

- <doc:TSCBasic/DiagnosticsEngine>
- <doc:SwiftDriver/Triple>
- <doc:SwiftDriver/FileType>
- <doc:SwiftDriver/VirtualPath>
- <doc:SwiftDriver/TypedVirtualPath>

