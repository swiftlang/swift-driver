//===----------------- ClangModuleBuildJobCache.swift ---------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Maps tuples (ModuleDependencyId, [String]), where [String] is an array of pcm build opitions,
/// to the job used to build this module with these specified build options.
struct ClangModuleBuildJobCache {

  /// As tuples cannot be Hashable, wrap (ModuleDependencyId, [String]) into a struct pair
  private struct ModuleArgumentPair : Hashable {
    let moduleId: ModuleDependencyId
    let buildArgs: [String]
  }

  private var cache: [ModuleArgumentPair: Job] = [:]

  var allJobs: [Job] {
    return Array(cache.values)
  }

  subscript(index: (ModuleDependencyId, [String])) -> Job? {
      get {
        return cache[ModuleArgumentPair(moduleId: index.0, buildArgs: index.1)]
      }
      set(newValue) {
        cache[ModuleArgumentPair(moduleId: index.0, buildArgs: index.1)] = newValue
      }
  }
}

