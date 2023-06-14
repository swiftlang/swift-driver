# Incremental Builds

A compilation mode that tries to schedule the rebuilding of Swift files with
changes and their dependents.

## Overview

An *incremental build* is a resource-saving compilation mode that attempts
to detect and rebuild only those files that have changed between successive
invocations of the driver. By communicating with the frontends it spawns to
determine their dependencies, the driver is able to intelligently schedule
minimal rebuilds of Swift modules.

## Introduction

The finest unit of scheduling the Swift driver is concerned about is an
individual file. When the driver is invoked, every file in the module is passed
to it as an input. It is up to the incremental build to sort these inputs into
jobs that should be run, and jobs that should be skipped.

The Swift compilation model includes one more wrinkle: the compilation of one
file may introduce dependencies on another file that needs to rebuild afterward.
Therefore, the incremental build state can be continuously queried to both
integrate new dependencies and discover additional compilation jobs to run. This
implies that the incremental build must be run *to a fixpoint* in order for
it to complete.

## Communicating Dependencies

The Swift driver includes built-in facilities for reading incremental dependnecy
information produced by the Swift frontend called `.swiftdeps` files. These
files contain serialized dependency information on both a per-file and
per-declaration basis. The format of swiftdeps files is an implementation detail
of the driver and frontends, and version mismatches will cause the incremental
build to be cancelled and a full rebuild to be performed in its place.

Generally, a `.swiftdeps` file contains the names of dependencies that the file
exports to other files - called *provides* - and dependencies that the file
imports from other files - called *depends*. To see this system in abstract,
consider the following "file" of Swift declarations:

```
public struct Foo { // (1)
  var bar: Bar // (3)
}

public struct Bar { // (2)
  var baz: Int // (4)
}
```

This file *provides* the types `Foo` and `Bar` as well as their members
`Foo.bar` and `Bar.baz`. There are also dependencies between `Foo` and `Bar`
because the type of `Foo.bar` depends upon `Bar`, and a dependency between
`Bar` and Swift's `Int` type because of `Bar.baz`.

Notably, the provides of a file need not be limited to the declarations it
contains. Provides are often composed transitively from other provided
declarations used in the file. For example,

```
class B : A {} // This file provides both A and B
```

This may seem odd at first blush as this file only declares the class type `B`,
not the superclass `A`. But consider that any file that uses the subclass `B`
also *implicitly uses the superclass A*. If `A` were to change in a way that
required a rebuild, we would want those transitive dependencies to rebuild as
well!

In general, after collecting all of the provides and depends for a file, the
result is an enormous [multi-graph](https://en.wikipedia.org/wiki/Multigraph)
of dependency edges between Swift files. The Swift driver integrates each
`.swiftdeps` file that corresponds to a `.swift` file into a
``SwiftDriver/ModuleDependencyGraph`` that then forms the backbone of
the dependency analysis procedures that power the incremental build.

## Constructing the Incremental Build

Computing the set of files that must be rebuilt is a continuous process of
dynamically discovering, integrating, and scheduling dependencies. A high-level
summary of the incremental build state machine is provided in the following
diagram:

```
                                                                              ┌─────────────────────────────────────────────────┐
                                                                              │                                                 │
                            ┌──────┐                     ┌──────────┐         ▼                                                 │
                            │ Yes! │   ┏━━━━━━━━━━━━━┓   │ Success! │   ┏━━━━━━━━━━━┓                                           │
                        ┌───┴──────┴──▶┃ Read Priors ┃─┬─┴──────────┴──▶┃ Integrate ┃                                           │
                        │              ┗━━━━━━━━━━━━━┛ │                ┗━━━━━━━━━━━┛                                           │
                        │                              │                      │                                                 │
            ┌─────────┐ │                              ├────────┐             ├──────────────┐                                  │
┏━━━━━━━━┓  │ Priors? │ │                              │ Error! │             │  Discovered  │                                  │
┃ Start! ┃──┴─────────┴─┴─┐                            ├────────┘             │Dependencies? │                                  │
┗━━━━━━━━┛                │                            │                      ├──────────────┘┌──────┐                          │
                          │                            │                      │               │ Yes! │  ┏━━━━━━━━━━━━━━━━━━━━┓  │
                          │    ┌──────┐                ▼                      └────────────┬──┴──────┴─▶┃ Schedule Next Wave ┃──┘
                          │    │ Nope │    ┏━━━━━━━━━━━━━━━━━━━━━━━┓                ┌──────┤            ┗━━━━━━━━━━━━━━━━━━━━┛
                          └────┴──────┴───▶┃ Schedule Full Rebuild ┃─────────┐      │ Nope │
                                           ┗━━━━━━━━━━━━━━━━━━━━━━━┛         │      └──────┤
                                                                             │             │
                                                                             │             │
                                                                             │             ▼
                                                                             │         ┏━━━━━━━┓
                                                                             └────────▶┃ Done! ┃
                                                                                       ┗━━━━━━━┛
```

The build begins by examining "priors" - data left behind by the last compilation
session. If no data is found, the Driver considers the incremental build to be
a lost cause and schedules a full rebuild in order to gather `.swiftdeps` files
it can use to reconstruct this prior data.

Assuming priors are present, they are deserialized and any dependency
information they contain is integrated into the driver's dependency graph. Next,
the modification time of any files is examined. If these modification times do
not match the driver's last expected modification time, those files are
immediately scheduled for rebuilding. Using the information from the prior build,
we can also determine the files that directly depend upon those modified files
and pull them in for rebuilding. The set of modified files and their direct
dependents is colloquially referred to as the *first wave* of compilation jobs.

As the name *first wave* implies, additional discovered dependencies in the
modified files can cause the formation of further waves of compilation. As
each frontend job finishes compiling a swift file, it lays down a new
`.swiftdeps` file that the driver picks up and integrates into the module
dependency graph. New edges are added, and old edges removed, thus keeping
the module dependency graph up to date with the current state of the user's code
at that moment in time.

Eventually, the incremental build either exhausts the set of input files it
must rebuild, or runs into an error during compilation that requires the build
to halt. Either way, the driver writes down the state of the build, then flushes
the module dependency graph to disk so the entire process can begin anew.

## Topics

### State Management

- <doc:SwiftDriver/IncrementalCompilationState>

### Dependency Graphs

- <doc:SwiftDriver/ModuleDependencyGraph>
- <doc:SwiftDriver/SourceFileDependencyGraph>
