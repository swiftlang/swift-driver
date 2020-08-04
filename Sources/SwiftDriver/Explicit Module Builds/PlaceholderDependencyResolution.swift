//===--------------- PlaceholderDependencyResolution.swift ----------------===//
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
import TSCBasic
import TSCUtility
import Foundation

extension ExplicitModuleBuildHandler {
  // Building a Swift module in Explicit Module Build mode requires passing all of its module
  // dependencies as explicit arguments to the build command.
  //
  // When the driver's clients (build systems) are planning a build that involves multiple
  // Swift modules, planning for each individual module may take place before its dependencies
  // have been built. This means that the dependency scanning action will not be able to
  // discover such modules. In such cases, the clients must provide the driver with information
  // about such external dependencies, including the path to where their compiled .swiftmodule
  // will be located, once built, and a full inter-module dependency graph for each such dependence.
  //
  // The driver will pass down the information about such external dependencies to the scanning
  // action, which will generate `placeholder` swift modules for them in the resulting dependency
  // graph. The driver will then use the complete dependency graph provided by
  // the client for each external dependency and use it to "resolve" the dependency's "placeholder"
  // module.
  //
  // Consider an example SwiftPM package with two targets: target B, and target A, where A
  // depends on B:
  // SwiftPM will process targets in a topological order and “bubble-up” each target’s
  // inter-module dependency graph to its dependees. First, SwiftPM will process B, and be
  // able to plan its full build because it does not have any target dependencies. Then the
  // driver is tasked with planning a build for A. SwiftPM will pass as input to the driver
  // the module dependency graph of its target’s dependencies, in this case, just the
  // dependency graph of B. The scanning action for module A will contain a placeholder module B,
  // which the driver will then resolve using B's full dependency graph provided by the client.

  /// Resolve all placeholder dependencies using external dependency information provided by the client
  mutating public func resolvePlaceholderDependencies() throws {
    let placeholderModules = dependencyGraph.modules.keys.filter {
      if case .swiftPlaceholder(_) = $0 {
        return true
      }
      return false
    }

    // Resolve all placeholder modules
    for moduleId in placeholderModules {
      guard let (placeholderModulePath, placeholderDependencyGraph) =
              externalDependencyArtifactMap[moduleId] else {
        throw Driver.Error.missingExternalDependency(moduleId.moduleName)
      }
      try resolvePlaceholderDependency(placeholderModulePath: placeholderModulePath,
                                       placeholderDependencyGraph: placeholderDependencyGraph)
    }
  }

  /// Merge a given external module's dependency graph in place of a placeholder dependency
  mutating public func resolvePlaceholderDependency(placeholderModulePath: AbsolutePath,
                                                    placeholderDependencyGraph: InterModuleDependencyGraph)
  throws {
    // For every Swift module in the placeholder dependency graph, generate a new module info
    // containing only the pre-compiled module path, and insert it into the current module's
    // dependency graph, replacing equivalent (non pre-built) modules, if necessary.
    //
    // For every Clang module in the placeholder dependency graph, because PCM modules file names
    // encode the specific pcmArguments of their dependees, we cannot use pre-built files here
    // because we do not always know which target they corrspond to, nor do we have a way to map
    // from a certain target to a specific pcm file. Because of this, all PCM dependencies, direct
    // and transitive, have to be built for all modules.
    for (moduleId, moduleInfo) in placeholderDependencyGraph.modules {
      switch moduleId {
        case .swift(_):
          // Compute the compiled module path for this module.
          // If this module is the placeholder itself, this information was passed from SwiftPM
          // If this module is any other swift module, then the compiled module path is
          // a part of the details field.
          // Otherwise (for most other dependencies), it is the modulePath of the moduleInfo node.
          let compiledModulePath : String
          if moduleId.moduleName == placeholderDependencyGraph.mainModuleName {
            compiledModulePath = placeholderModulePath.description
          } else if case .swift(let details) = moduleInfo.details,
                    let explicitModulePath = details.explicitCompiledModulePath {
            compiledModulePath = explicitModulePath
          } else {
            compiledModulePath = moduleInfo.modulePath.description
          }

          let swiftDetails =
            SwiftModuleDetails(compiledModulePath: compiledModulePath)
          let newInfo = ModuleInfo(modulePath: moduleInfo.modulePath.description,
                                   sourceFiles: nil,
                                   directDependencies: moduleInfo.directDependencies,
                                   details: ModuleInfo.Details.swift(swiftDetails))
          try insertOrReplaceModule(moduleId: moduleId, moduleInfo: newInfo)
        case .clang(_):
          if dependencyGraph.modules[moduleId] == nil {
            dependencyGraph.modules[moduleId] = moduleInfo
          }
        case .swiftPlaceholder(_):
          try insertOrReplaceModule(moduleId: moduleId, moduleInfo: moduleInfo)
      }
    }
  }

  /// Insert a module into the handler's dependency graph. If a module with this identifier already exists,
  /// replace it's module with a moduleInfo that contains a path to an existing prebuilt .swiftmodule
  mutating public func insertOrReplaceModule(moduleId: ModuleDependencyId,
                                             moduleInfo: ModuleInfo) throws {
    // Check for placeholders to be replaced
    if dependencyGraph.modules[ModuleDependencyId.swiftPlaceholder(moduleId.moduleName)] != nil {
      try replaceModule(originalId: .swiftPlaceholder(moduleId.moduleName), replacementId: moduleId,
                        replacementInfo: moduleInfo)
    }
    // Check for modules with the same Identifier, and replace if found
    else if dependencyGraph.modules[moduleId] != nil {
      try replaceModule(originalId: moduleId, replacementId: moduleId, replacementInfo: moduleInfo)
    // This module is new to the current dependency graph
    } else {
      dependencyGraph.modules[moduleId] = moduleInfo
    }
  }

  /// Replace a module with a new one. Replace all references to the original module in other modules' dependencies
  /// with the new module.
  mutating public func replaceModule(originalId: ModuleDependencyId,
                                     replacementId: ModuleDependencyId,
                                     replacementInfo: ModuleInfo) throws {
    dependencyGraph.modules.removeValue(forKey: originalId)
    dependencyGraph.modules[replacementId] = replacementInfo
    for moduleId in dependencyGraph.modules.keys {
      var moduleInfo = dependencyGraph.modules[moduleId]!
      // Skip over other placeholders, they do not have dependencies
      if case .swiftPlaceholder(_) = moduleId {
        continue
      }
      if let originalModuleIndex = moduleInfo.directDependencies?.firstIndex(of: originalId) {
        moduleInfo.directDependencies![originalModuleIndex] = replacementId;
      }
      dependencyGraph.modules[moduleId] = moduleInfo
    }
  }
}

/// Used for creating new module infos during placeholder dependency resolution
/// Modules created this way only contain a path to a pre-built module file.
extension SwiftModuleDetails {
  public init(compiledModulePath: String) {
    self.moduleInterfacePath = nil
    self.compiledModuleCandidates = nil
    self.explicitCompiledModulePath = compiledModulePath
    self.bridgingHeaderPath = nil
    self.bridgingSourceFiles = nil
    self.commandLine = nil
    self.extraPcmArgs = nil
  }
}
