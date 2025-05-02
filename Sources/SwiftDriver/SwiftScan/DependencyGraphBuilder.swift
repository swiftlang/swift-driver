//===--- DependencyGraphBuilder.swift -------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_implementationOnly import CSwiftScan

internal extension SwiftScan {
  /// From a reference to a binary-format dependency graph returned by libSwiftScan,
  /// construct an instance of an `InterModuleDependencyGraph`.
  func constructGraph(from scannerGraphRef: swiftscan_dependency_graph_t,
                      moduleAliases: [String: String]?) throws
  -> InterModuleDependencyGraph {
    let mainModuleNameRef =
      api.swiftscan_dependency_graph_get_main_module_name(scannerGraphRef)
    let mainModuleName = try toSwiftString(mainModuleNameRef)

    let dependencySetRefOrNull = api.swiftscan_dependency_graph_get_dependencies(scannerGraphRef)
    guard let dependencySetRef = dependencySetRefOrNull else {
      throw DependencyScanningError.missingField("dependency_graph.dependencies")
    }

    var resultGraph = InterModuleDependencyGraph(mainModuleName: mainModuleName)
    // Turn the `swiftscan_dependency_set_t` into an array of `swiftscan_dependency_info_t`
    // references we can iterate through in order to construct `ModuleInfo` objects.
    let moduleRefArray = Array(UnsafeBufferPointer(start: dependencySetRef.pointee.modules,
                                                    count: Int(dependencySetRef.pointee.count)))
    for moduleRefOrNull in moduleRefArray {
      guard let moduleRef = moduleRefOrNull else {
        throw DependencyScanningError.missingField("dependency_set_t.modules[_]")
      }
      let (moduleId, moduleInfo) = try constructModuleInfo(from: moduleRef, moduleAliases: moduleAliases)
      resultGraph.modules[moduleId] = moduleInfo
    }

    return resultGraph
  }

  /// From a reference to a binary-format set of module imports return by libSwiftScan pre-scan query,
  /// construct an instance of an `InterModuleDependencyImports` set
  func constructImportSet(from importSetRef: swiftscan_import_set_t,
                          with moduleAliases: [String: String]?) throws
  -> InterModuleDependencyImports {
    guard let importsRef = api.swiftscan_import_set_get_imports(importSetRef) else {
      throw DependencyScanningError.missingField("import_set.imports")
    }
    return InterModuleDependencyImports(imports: try toSwiftStringArray(importsRef.pointee), moduleAliases: moduleAliases)
  }
}

private extension SwiftScan {
  /// From a reference to a binary-format module dependency module info returned by libSwiftScan,
  /// construct an instance of an `ModuleInfo` as used by the driver
  func constructModuleInfo(from moduleInfoRef: swiftscan_dependency_info_t,
                           moduleAliases: [String: String]?)
  throws -> (ModuleDependencyId, ModuleInfo) {
    // Decode the module name and module kind
    let encodedModuleName =
      try toSwiftString(api.swiftscan_module_info_get_module_name(moduleInfoRef))
    let moduleId = try decodeModuleNameAndKind(from: encodedModuleName, moduleAliases: moduleAliases)

    // Decode module path and source file locations
    let modulePathStr = try toSwiftString(api.swiftscan_module_info_get_module_path(moduleInfoRef))
    let modulePath = TextualVirtualPath(path: try VirtualPath.intern(path: modulePathStr))
    let sourceFiles: [String]?
    if let sourceFilesSetRef = api.swiftscan_module_info_get_source_files(moduleInfoRef) {
      sourceFiles = try toSwiftStringArray(sourceFilesSetRef.pointee)
    } else {
      sourceFiles = nil
    }

    // Decode all dependencies of this module
    let directDependencies: [ModuleDependencyId]?
    if let encodedDirectDepsRef = api.swiftscan_module_info_get_direct_dependencies(moduleInfoRef) {
      let encodedDirectDependencies = try toSwiftStringArray(encodedDirectDepsRef.pointee)
      directDependencies =
      try encodedDirectDependencies.map { try decodeModuleNameAndKind(from: $0, moduleAliases: moduleAliases) }
    } else {
      directDependencies = nil
    }

    var linkLibraries: [LinkLibraryInfo] = []
    if supportsLinkLibraries {
      let linkLibrarySetRefOrNull = api.swiftscan_module_info_get_link_libraries(moduleInfoRef)
      guard let linkLibrarySetRef = linkLibrarySetRefOrNull else {
        throw DependencyScanningError.missingField("dependency_graph.link_libraries")
      }
      // Turn the `swiftscan_dependency_set_t` into an array of `swiftscan_dependency_info_t`
      // references we can iterate through in order to construct `ModuleInfo` objects.
      let linkLibraryRefArray = Array(UnsafeBufferPointer(start: linkLibrarySetRef.pointee.link_libraries,
                                                          count: Int(linkLibrarySetRef.pointee.count)))
      for linkLibraryRefOrNull in linkLibraryRefArray {
        guard let linkLibraryRef = linkLibraryRefOrNull else {
          throw DependencyScanningError.missingField("dependency_set_t.link_libraries[_]")
        }
        linkLibraries.append(try constructLinkLibrayInfo(from: linkLibraryRef))
      }
    }

    guard let moduleDetailsRef = api.swiftscan_module_info_get_details(moduleInfoRef) else {
      throw DependencyScanningError.missingField("modules[\(moduleId)].details")
    }
    let details = try constructModuleDetails(from: moduleDetailsRef,
                                             moduleAliases: moduleAliases)

    return (moduleId, ModuleInfo(modulePath: modulePath, sourceFiles: sourceFiles,
                                 directDependencies: directDependencies,
                                 linkLibraries: linkLibraries,
                                 details: details))
  }

  func constructLinkLibrayInfo(from linkLibraryInfoRef: swiftscan_link_library_info_t) throws -> LinkLibraryInfo {
    return LinkLibraryInfo(linkName: try toSwiftString(api.swiftscan_link_library_info_get_link_name(linkLibraryInfoRef)),
                             isFramework: api.swiftscan_link_library_info_get_is_framework(linkLibraryInfoRef),
                             shouldForceLoad: api.swiftscan_link_library_info_get_should_force_load(linkLibraryInfoRef))
  }

  /// From a reference to a binary-format module info details object info returned by libSwiftScan,
  /// construct an instance of an `ModuleInfo`.Details as used by the driver.
  /// The object returned by libSwiftScan is a union so ensure to execute dependency-specific queries.
  func constructModuleDetails(from moduleDetailsRef: swiftscan_module_details_t,
                              moduleAliases: [String: String]?)
  throws -> ModuleInfo.Details {
    let moduleKind = api.swiftscan_module_detail_get_kind(moduleDetailsRef)
    switch moduleKind {
      case SWIFTSCAN_DEPENDENCY_INFO_SWIFT_TEXTUAL:
        return .swift(try constructSwiftTextualModuleDetails(from: moduleDetailsRef,
                                                             moduleAliases: moduleAliases))
      case SWIFTSCAN_DEPENDENCY_INFO_SWIFT_BINARY:
        return .swiftPrebuiltExternal(try constructSwiftBinaryModuleDetails(from: moduleDetailsRef))
      case SWIFTSCAN_DEPENDENCY_INFO_SWIFT_PLACEHOLDER:
        return .swiftPlaceholder(try constructPlaceholderModuleDetails(from: moduleDetailsRef))
      case SWIFTSCAN_DEPENDENCY_INFO_CLANG:
        return .clang(try constructClangModuleDetails(from: moduleDetailsRef))
      default:
        throw DependencyScanningError.unsupportedDependencyDetailsKind(Int(moduleKind.rawValue))
    }
  }

  /// Construct a `SwiftModuleDetails` from a `swiftscan_module_details_t` reference
  func constructSwiftTextualModuleDetails(from moduleDetailsRef: swiftscan_module_details_t,
                                          moduleAliases: [String: String]?)
  throws -> SwiftModuleDetails {
    let moduleInterfacePath =
      try getOptionalPathDetail(from: moduleDetailsRef,
                                using: api.swiftscan_swift_textual_detail_get_module_interface_path)
    let compiledModuleCandidates =
      try getOptionalPathArrayDetail(from: moduleDetailsRef,
                                     using: api.swiftscan_swift_textual_detail_get_compiled_module_candidates)
    let bridgingHeaderPath =
      try getOptionalPathDetail(from: moduleDetailsRef,
                                using: api.swiftscan_swift_textual_detail_get_bridging_header_path)
    let bridgingSourceFiles =
      try getOptionalPathArrayDetail(from: moduleDetailsRef,
                                     using: api.swiftscan_swift_textual_detail_get_bridging_source_files)
    let bridgingHeaderDependencies =
      try getOptionalStringArrayDetail(from: moduleDetailsRef,
                                       using: api.swiftscan_swift_textual_detail_get_bridging_module_dependencies)
    let bridgingHeader: BridgingHeader?
    if let resolvedBridgingHeaderPath = bridgingHeaderPath {
      bridgingHeader = BridgingHeader(path: resolvedBridgingHeaderPath,
                                      sourceFiles: bridgingSourceFiles ?? [],
                                      moduleDependencies: bridgingHeaderDependencies ?? [])
    } else {
      bridgingHeader = nil
    }

    let commandLine =
      try getOptionalStringArrayDetail(from: moduleDetailsRef,
                                       using: api.swiftscan_swift_textual_detail_get_command_line)
    let bridgingPchCommandLine = supportsBridgingHeaderPCHCommand ?
      try getOptionalStringArrayDetail(from: moduleDetailsRef,
                                       using: api.swiftscan_swift_textual_detail_get_bridging_pch_command_line) : nil
    let contextHash =
      try getOptionalStringDetail(from: moduleDetailsRef,
                          using: api.swiftscan_swift_textual_detail_get_context_hash)
    let isFramework = api.swiftscan_swift_textual_detail_get_is_framework(moduleDetailsRef)
    let moduleCacheKey = supportsCaching ?  try getOptionalStringDetail(from: moduleDetailsRef,
                                                     using: api.swiftscan_swift_textual_detail_get_module_cache_key) : nil
    let chainedBridgingHeaderPath = supportsChainedBridgingHeader ?
      try getOptionalStringDetail(from: moduleDetailsRef, using: api.swiftscan_swift_textual_detail_get_chained_bridging_header_path) : nil
    let chainedBridgingHeaderContent = supportsChainedBridgingHeader ?
      try getOptionalStringDetail(from: moduleDetailsRef, using: api.swiftscan_swift_textual_detail_get_chained_bridging_header_content) : nil

    // Decode all dependencies of this module
    let swiftOverlayDependencies: [ModuleDependencyId]?
    if supportsSeparateSwiftOverlayDependencies,
       let encodedOverlayDepsRef = api.swiftscan_swift_textual_detail_get_swift_overlay_dependencies(moduleDetailsRef) {
      let encodedOverlayDependencies = try toSwiftStringArray(encodedOverlayDepsRef.pointee)
      swiftOverlayDependencies =
        try encodedOverlayDependencies.map { try decodeModuleNameAndKind(from: $0, moduleAliases: moduleAliases) }
    } else {
      swiftOverlayDependencies = nil
    }

    return SwiftModuleDetails(moduleInterfacePath: moduleInterfacePath,
                              compiledModuleCandidates: compiledModuleCandidates,
                              bridgingHeader: bridgingHeader,
                              commandLine: commandLine,
                              bridgingPchCommandLine : bridgingPchCommandLine,
                              contextHash: contextHash,
                              isFramework: isFramework,
                              swiftOverlayDependencies: swiftOverlayDependencies,
                              moduleCacheKey: moduleCacheKey,
                              chainedBridgingHeaderPath: chainedBridgingHeaderPath,
                              chainedBridgingHeaderContent: chainedBridgingHeaderContent)
  }

  /// Construct a `SwiftPrebuiltExternalModuleDetails` from a `swiftscan_module_details_t` reference
  func constructSwiftBinaryModuleDetails(from moduleDetailsRef: swiftscan_module_details_t)
  throws -> SwiftPrebuiltExternalModuleDetails {
    let compiledModulePath =
      try getPathDetail(from: moduleDetailsRef,
                        using: api.swiftscan_swift_binary_detail_get_compiled_module_path,
                        fieldName: "swift_binary_detail.compiledModulePath")
    let moduleDocPath =
      try getOptionalPathDetail(from: moduleDetailsRef,
                                using: api.swiftscan_swift_binary_detail_get_module_doc_path)
    let moduleSourceInfoPath =
      try getOptionalPathDetail(from: moduleDetailsRef,
                                using: api.swiftscan_swift_binary_detail_get_module_source_info_path)

    let headerDependencies: [TextualVirtualPath]?
    if supportsBinaryModuleHeaderDependencies {
      headerDependencies = try getOptionalPathArrayDetail(from: moduleDetailsRef,
                                                          using: api.swiftscan_swift_binary_detail_get_header_dependencies)
    } else if supportsBinaryModuleHeaderDependency,
              let header = try getOptionalPathDetail(from: moduleDetailsRef,
                                                     using: api.swiftscan_swift_binary_detail_get_header_dependency) {
      headerDependencies = [header]
    } else {
      headerDependencies = nil
    }

    let isFramework: Bool
    if hasBinarySwiftModuleIsFramework {
      isFramework = api.swiftscan_swift_binary_detail_get_is_framework(moduleDetailsRef)
    } else {
      isFramework = false
    }

    let headerDependencyModuleDependencies: [ModuleDependencyId]? =
      hasBinarySwiftModuleHeaderModuleDependencies ?
        try getOptionalStringArrayDetail(from: moduleDetailsRef,
                                         using: api.swiftscan_swift_binary_detail_get_header_dependency_module_dependencies)?.map { .clang($0) } : nil

    let moduleCacheKey = supportsCaching ? try getOptionalStringDetail(from: moduleDetailsRef,
                                                     using: api.swiftscan_swift_binary_detail_get_module_cache_key) : nil

    return SwiftPrebuiltExternalModuleDetails(compiledModulePath: compiledModulePath,
                                              moduleDocPath: moduleDocPath,
                                              moduleSourceInfoPath: moduleSourceInfoPath,
                                              headerDependencyPaths: headerDependencies,
                                              headerDependencyModuleDependencies: headerDependencyModuleDependencies,
                                              isFramework: isFramework,
                                              moduleCacheKey: moduleCacheKey)
  }

  /// Construct a `SwiftPlaceholderModuleDetails` from a `swiftscan_module_details_t` reference
  func constructPlaceholderModuleDetails(from moduleDetailsRef: swiftscan_module_details_t)
  throws -> SwiftPlaceholderModuleDetails {
    let moduleDocPath =
      try getOptionalPathDetail(from: moduleDetailsRef,
                                using: api.swiftscan_swift_placeholder_detail_get_module_doc_path)
    let moduleSourceInfoPath =
      try getOptionalPathDetail(from: moduleDetailsRef,
                                using: api.swiftscan_swift_placeholder_detail_get_module_source_info_path)
    return SwiftPlaceholderModuleDetails(moduleDocPath: moduleDocPath,
                                         moduleSourceInfoPath: moduleSourceInfoPath)
  }

  /// Construct a `ClangModuleDetails` from a `swiftscan_module_details_t` reference
  func constructClangModuleDetails(from moduleDetailsRef: swiftscan_module_details_t)
  throws -> ClangModuleDetails {
    let moduleMapPath =
      try getPathDetail(from: moduleDetailsRef,
                        using: api.swiftscan_clang_detail_get_module_map_path,
                        fieldName: "clang_detail.moduleMapPath")
    let contextHash =
      try getStringDetail(from: moduleDetailsRef,
                          using: api.swiftscan_clang_detail_get_context_hash,
                          fieldName: "clang_detail.contextHash")
    let commandLine =
      try getStringArrayDetail(from: moduleDetailsRef,
                               using: api.swiftscan_clang_detail_get_command_line,
                               fieldName: "clang_detail.commandLine")

    let moduleCacheKey = supportsCaching ? try getOptionalStringDetail(from: moduleDetailsRef,
                                                     using: api.swiftscan_clang_detail_get_module_cache_key) : nil

    return ClangModuleDetails(moduleMapPath: moduleMapPath,
                              contextHash: contextHash,
                              commandLine: commandLine,
                              moduleCacheKey: moduleCacheKey)
  }
}

internal extension SwiftScan {
  /// Convert a `swiftscan_string_ref_t` reference to a Swift `String`, assuming the reference is to a valid string
  /// (non-null)
  func toSwiftString(_ string_ref: swiftscan_string_ref_t) throws -> String {
    if string_ref.length == 0 {
      return ""
    }
    // If the string is of a positive length, the pointer cannot be null
    guard let dataPtr = string_ref.data else {
      throw DependencyScanningError.invalidStringPtr
    }
    return String(bytesNoCopy: UnsafeMutableRawPointer(mutating: dataPtr),
                  length: string_ref.length,
                  encoding: String.Encoding.utf8, freeWhenDone: false)!
  }

  /// Convert a `swiftscan_string_set_t` reference to a Swift `[String]`, assuming the individual string references
  /// are to a valid strings (non-null)
  func toSwiftStringArray(_ string_set: swiftscan_string_set_t) throws -> [String] {
    var result: [String] = []
    let stringRefArray = Array(UnsafeBufferPointer(start: string_set.strings,
                                                    count: Int(string_set.count)))
    for stringRef in stringRefArray {
      result.append(try toSwiftString(stringRef))
    }
    return result
  }

  /// Convert a `swiftscan_string_set_t` reference to a Swift `Set<String>`, assuming the individual string references
  /// are to a valid strings (non-null)
  func toSwiftStringSet(_ string_set: swiftscan_string_set_t) throws -> Set<String> {
    var result = Set<String>()
    let stringRefArray = Array(UnsafeBufferPointer(start: string_set.strings,
                                                    count: Int(string_set.count)))
    for stringRef in stringRefArray {
      result.insert(try toSwiftString(stringRef))
    }
    return result
  }
}

private extension SwiftScan {
  /// From a `swiftscan_module_details_t` reference, extract a `TextualVirtualPath?` detail using the specified API query
  func getOptionalPathDetail(from detailsRef: swiftscan_module_details_t,
                             using query: (swiftscan_module_details_t)
                              -> swiftscan_string_ref_t)
  throws -> TextualVirtualPath? {
    let strDetail = try getOptionalStringDetail(from: detailsRef, using: query)
    return strDetail != nil ? TextualVirtualPath(path: try VirtualPath.intern(path: strDetail!)) : nil
  }

  /// From a `swiftscan_module_details_t` reference, extract a `String?` detail using the specified API query
  func getOptionalStringDetail(from detailsRef: swiftscan_module_details_t,
                               using query: (swiftscan_module_details_t)
                                -> swiftscan_string_ref_t)
  throws -> String? {
    let detailRef = query(detailsRef)
    guard detailRef.length != 0 else { return nil }
    assert(detailRef.data != nil)
    return try toSwiftString(detailRef)
  }

  /// From a `swiftscan_module_details_t` reference, extract a `TextualVirtualPath` detail using the specified API
  /// query, making sure the reference is to a non-null (and non-empty) path.
  func getPathDetail(from detailsRef: swiftscan_module_details_t,
                     using query: (swiftscan_module_details_t) -> swiftscan_string_ref_t,
                     fieldName: String)
  throws -> TextualVirtualPath {
    let strDetail = try getStringDetail(from: detailsRef, using: query, fieldName: fieldName)
    return TextualVirtualPath(path: try VirtualPath.intern(path: strDetail))
  }

  /// From a `swiftscan_module_details_t` reference, extract a `String` detail using the specified API query,
  /// making sure the reference is to a non-null (and non-empty) string.
  func getStringDetail(from detailsRef: swiftscan_module_details_t,
                       using query: (swiftscan_module_details_t) -> swiftscan_string_ref_t,
                       fieldName: String) throws -> String {
    guard let result = try getOptionalStringDetail(from: detailsRef, using: query) else {
      throw DependencyScanningError.missingField(fieldName)
    }
    return result
  }

  /// From a `swiftscan_module_details_t` reference, extract a `[TextualVirtualPath]?` detail using the specified API
  /// query
  func getOptionalPathArrayDetail(from detailsRef: swiftscan_module_details_t,
  using query: (swiftscan_module_details_t)
    -> UnsafeMutablePointer<swiftscan_string_set_t>?)
  throws -> [TextualVirtualPath]? {
    guard let strArrDetail = try getOptionalStringArrayDetail(from: detailsRef, using: query) else {
      return nil
    }
    return try strArrDetail.map { TextualVirtualPath(path: try VirtualPath.intern(path: $0)) }
  }

  /// From a `swiftscan_module_details_t` reference, extract a `[String]?` detail using the specified API query
  func getOptionalStringArrayDetail(from detailsRef: swiftscan_module_details_t,
                                    using query: (swiftscan_module_details_t)
                                      -> UnsafeMutablePointer<swiftscan_string_set_t>?)
  throws -> [String]? {
    guard let detailRef = query(detailsRef) else { return nil }
    return try toSwiftStringArray(detailRef.pointee)
  }

  /// From a `swiftscan_module_details_t` reference, extract a `[String]` detail using the specified API query,
  /// making sure individual string references are non-null (and non-empty) strings.
  func getStringArrayDetail(from detailsRef: swiftscan_module_details_t,
                            using query: (swiftscan_module_details_t)
                                      -> UnsafeMutablePointer<swiftscan_string_set_t>?,
                            fieldName: String) throws -> [String] {
    guard let result = try getOptionalStringArrayDetail(from: detailsRef, using: query) else {
      throw DependencyScanningError.missingField(fieldName)
    }
    return result
  }
}

private extension SwiftScan {
  /// Decode the module name returned by libSwiftScan into a `ModuleDependencyId`
  /// libSwiftScan encodes the module's name using the following scheme:
  /// `<module-kind>:<module-name>`
  /// where `module-kind` is one of:
  /// "swiftTextual"
  /// "swiftBinary"
  /// "swiftPlaceholder"
  /// "clang""
  func decodeModuleNameAndKind(from encodedName: String,
                               moduleAliases: [String: String]?) throws -> ModuleDependencyId {
    switch encodedName {
      case _ where encodedName.starts(with: "swiftTextual:"):
      var namePart = String(encodedName.suffix(encodedName.count - "swiftTextual:".count))
      if let moduleAliases = moduleAliases, let realName = moduleAliases[namePart] {
        namePart = realName
      }
      return .swift(namePart)
      case _ where encodedName.starts(with: "swiftBinary:"):
        var namePart = String(encodedName.suffix(encodedName.count - "swiftBinary:".count))
        if let moduleAliases = moduleAliases, let realName = moduleAliases[namePart] {
          namePart = realName
        }
        return .swiftPrebuiltExternal(namePart)
      case _ where encodedName.starts(with: "swiftPlaceholder:"):
        return .swiftPlaceholder(String(encodedName.suffix(encodedName.count - "swiftPlaceholder:".count)))
      case _ where encodedName.starts(with: "clang:"):
        return .clang(String(encodedName.suffix(encodedName.count - "clang:".count)))
      default:
        throw DependencyScanningError.moduleNameDecodeFailure(encodedName)
    }
  }
}
