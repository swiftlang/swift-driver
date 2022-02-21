# Explicit Module Builds

Fast scanning and reporting of modular dependencies.

## Introduction

The Swift driver provides facilities for quickly scanning the Swift source files
to identify explicit dependencies on other Swift modules, C headers, frameworks,
modulemaps, and other inputs that may affect the structure and contents of a
module. This information is used to proactively build a complete picture of
the entire set of dependencies of a module which will enable build systems to
perform faster, more robust rebuilds.

## Fast Dependency Scanning

The dependency information for a module can come from a variety of sources:

- Serialized swift module files, by reading the module header
- Swift interface files, by parsing the source code to find imports
- Swift source files, by parsing the source code to find imports
- Clang modules, using Clang's fast dependency scanning tool
- Bridging headers, including the source files and modules they depend on

Each of these does not require more work than parsing or module loading
to discover dependencies, making them ideal candidates for rapidly sourcing
dependency information.

The Swift Driver schedules a special frontend job to perform all of this
dependency scanning up front. The information is then reported back to any
clients that wish to determine the jobs they need to run to rebuild dependent
modules *before* they rebuild the current Swift module.

## What's So Bad About Implicit Module Builds?

One of the primary tasks of a build system is determining the number, order, and
kind of dependencies between different build products. This information helps
the build system determine which tools it needs to invoke to regenerate these
products when changes occur. Make-style build systems require an explicit
declaration of targets and their dependencies that makes this kind of analysis
relatively straightforward. But some build systems try to be intelligent about
the kinds of dependencies they can search for without explicit declarations.

Sometimes, even the tools themselves try to be intelligent about build
dependencies. For example, the Swift Driver reports back a curious thing to
build systems that care to ask for make-style dependencies: every file depends
upon every other file. This dense dependency graph allows the driver to take
control of rebuilding Swift files, and ensures that
incremental builds (see <doc:IncrementalBuilds>) work with these
systems out of the box.

Further implicit build schemes are implemented by both Clang and Swift to
rebuild their respective notion of modules when metadata mismatches are
detected. Both compilers maintain a cache of these implicitly-built modules to
speed up future queries for the same module. As these caches are rebuilt on
demand, the dependency on the rebuild is *not* reported to the build system -
it happens *implicitly*.

Implicit module builds complicate the compilers in a number of interesting
ways. Each compiler and its associated driver must become a miniature module
build system to accommodate requests to rebuild modules (which may, itself,
involve rebuilding yet more modules), which comes with lots of maintenance
overhead. What's more, as these rebuilds are hidden from both the user and the
build tools, certain compilations may appear to take an inordinate amount of
time as caches are repopulated, then appear to take no time at all at a later
point. Because the same module may be requested many times during the parallel
rebuild of targets, the caches are constantly under heavy contention from
multiple processes that are trying to both read and write into them, which leads
to incredibly subtle problems when file systems, locks, and concurrency bugs
conspire together. Finally, the build system will generally have some
user-derived knowledge of the amount of parallelism needed to accomplish
a given task. The compilers performing implicit module builds, by contrast, are
not given this information. This can lead to an explosion of tasks to rebuild
and repopulate the module cache that can and do quickly overwhelm a
user's machine.

All of these problems could be avoided by returning to a more declarative
model where dependencies on modules being rebuilt is provided to the build
systems up front.

