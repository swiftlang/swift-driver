//===------------------------ SwiftScan.swift -----------------------------===//
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

import func Foundation.strdup
import func Foundation.free
import class Foundation.JSONDecoder
import struct Foundation.Data

import protocol TSCBasic.DiagnosticData
import struct TSCBasic.AbsolutePath
import struct TSCBasic.Diagnostic

public enum DependencyScanningError: Error, DiagnosticData {
  case missingRequiredSymbol(String)
  case dependencyScanFailed
  case failedToInstantiateScanner
  case casError(String)
  case missingField(String)
  case moduleNameDecodeFailure(String)
  case unsupportedDependencyDetailsKind(Int)
  case invalidStringPtr
  case scanningLibraryInvocationMismatch(AbsolutePath, AbsolutePath)
  case scanningLibraryNotFound(AbsolutePath)
  case argumentQueryFailed

  public var description: String {
    switch self {
      case .missingRequiredSymbol(let symbolName):
        return "libSwiftScan missing required symbol: '\(symbolName)'"
      case .dependencyScanFailed:
        return "libSwiftScan dependency scan query failed"
      case .failedToInstantiateScanner:
        return "libSwiftScan failed to create scanner instance"
      case .casError(let reason):
        return "libSwiftScan CAS error: \(reason)"
      case .missingField(let fieldName):
        return "libSwiftScan scan result missing required field: `\(fieldName)`"
      case .moduleNameDecodeFailure(let encodedName):
        return "Failed to decode dependency module name: `\(encodedName)`"
      case .unsupportedDependencyDetailsKind(let kindRawValue):
        return "Dependency module details field kind not supported: `\(kindRawValue)`"
      case .invalidStringPtr:
        return "Dependency module details contains a corrupted string reference"
      case .scanningLibraryInvocationMismatch(let path1, let path2):
        return "Dependency Scanning library differs across driver invocations: \(path1.description) and \(path2.description)"
      case .scanningLibraryNotFound(let path):
        return "Dependency Scanning library not found at path: \(path)"
      case .argumentQueryFailed:
        return "libSwiftScan supported compiler argument query failed"
    }
  }
}

@_spi(Testing) public struct ScannerDiagnosticPayload {
  @_spi(Testing) public let severity: Diagnostic.Behavior
  @_spi(Testing) public let message: String
}

internal extension swiftscan_diagnostic_severity_t {
  func toDiagnosticBehavior() -> Diagnostic.Behavior {
    switch self {
    case SWIFTSCAN_DIAGNOSTIC_SEVERITY_ERROR:
      return Diagnostic.Behavior.error
    case SWIFTSCAN_DIAGNOSTIC_SEVERITY_WARNING:
      return Diagnostic.Behavior.warning
    case SWIFTSCAN_DIAGNOSTIC_SEVERITY_NOTE:
      return Diagnostic.Behavior.note
    case SWIFTSCAN_DIAGNOSTIC_SEVERITY_REMARK:
      return Diagnostic.Behavior.remark
    default:
      return Diagnostic.Behavior.error
    }
  }
}

/// Wrapper for libSwiftScan, taking care of initialization, shutdown, and dispatching dependency scanning queries.
@_spi(Testing) public final class SwiftScan {
  /// The path to the libSwiftScan dylib.
  let path: AbsolutePath

  /// The handle to the dylib.
  let dylib: Loader.Handle

  /// libSwiftScan API functions.
  let api: swiftscan_functions_t;

  /// Instance of a scanner, which maintains shared state across scan queries.
  let scanner: swiftscan_scanner_t;

  /// Optional CAS instance.
  var cas: swiftscan_cas_t? = nil

  @_spi(Testing) public init(dylib path: AbsolutePath) throws {
    self.path = path
    #if os(Windows)
    self.dylib = try Loader.load(path.pathString, mode: [])
    #else
    self.dylib = try Loader.load(path.pathString, mode: [.lazy, .local, .first])
    #endif
    self.api = try swiftscan_functions_t(self.dylib)
    guard let scanner = api.swiftscan_scanner_create() else {
      throw DependencyScanningError.failedToInstantiateScanner
    }
    self.scanner = scanner
  }

  deinit {
    api.swiftscan_scanner_dispose(self.scanner)
    if let scan_cas = cas {
      api.swiftscan_cas_dispose(scan_cas)
    }
    // FIXME: is it safe to dlclose() swiftscan? If so, do that here.
    // For now, let the handle leak.
    dylib.leak()
  }

  func preScanImports(workingDirectory: AbsolutePath,
                      moduleAliases: [String: String]?,
                      invocationCommand: [String]) throws -> InterModuleDependencyImports {
    // Create and configure the scanner invocation
    let invocation = api.swiftscan_scan_invocation_create()
    defer { api.swiftscan_scan_invocation_dispose(invocation) }
    api.swiftscan_scan_invocation_set_working_directory(invocation,
                                                        workingDirectory
                                                          .description
                                                          .cString(using: String.Encoding.utf8))
    withArrayOfCStrings(invocationCommand) { invocationStringArray in
      api.swiftscan_scan_invocation_set_argv(invocation,
                                             Int32(invocationCommand.count),
                                             invocationStringArray)
    }

    let importSetRefOrNull = api.swiftscan_import_set_create(scanner, invocation)
    guard let importSetRef = importSetRefOrNull else {
      throw DependencyScanningError.dependencyScanFailed
    }

    let importSet = try constructImportSet(from: importSetRef, with: moduleAliases)
    // Free the memory allocated for the in-memory representation of the import set
    // returned by the scanner, now that we have translated it.
    api.swiftscan_import_set_dispose(importSetRef)
    return importSet
  }

  func scanDependencies(workingDirectory: AbsolutePath,
                        moduleAliases: [String: String]?,
                        invocationCommand: [String]) throws -> InterModuleDependencyGraph {
    // Create and configure the scanner invocation
    let invocation = api.swiftscan_scan_invocation_create()
    defer { api.swiftscan_scan_invocation_dispose(invocation) }
    api.swiftscan_scan_invocation_set_working_directory(invocation,
                                                        workingDirectory
                                                          .description
                                                          .cString(using: String.Encoding.utf8))
    withArrayOfCStrings(invocationCommand) { invocationStringArray in
      api.swiftscan_scan_invocation_set_argv(invocation,
                                             Int32(invocationCommand.count),
                                             invocationStringArray)
    }

    let graphRefOrNull = api.swiftscan_dependency_graph_create(scanner, invocation)
    guard let graphRef = graphRefOrNull else {
      throw DependencyScanningError.dependencyScanFailed
    }

    let dependencyGraph = try constructGraph(from: graphRef, moduleAliases: moduleAliases)
    // Free the memory allocated for the in-memory representation of the dependency
    // graph returned by the scanner, now that we have translated it into an
    // `InterModuleDependencyGraph`.
    api.swiftscan_dependency_graph_dispose(graphRef)
    return dependencyGraph
  }

  func batchScanDependencies(workingDirectory: AbsolutePath,
                             moduleAliases: [String: String]?,
                             invocationCommand: [String],
                             batchInfos: [BatchScanModuleInfo])
  throws -> [ModuleDependencyId: [InterModuleDependencyGraph]] {
    // Create and configure the scanner invocation
    let invocationRef = api.swiftscan_scan_invocation_create()
    defer { api.swiftscan_scan_invocation_dispose(invocationRef) }
    api.swiftscan_scan_invocation_set_working_directory(invocationRef,
                                                        workingDirectory
                                                          .description
                                                          .cString(using: String.Encoding.utf8))
    withArrayOfCStrings(invocationCommand) { invocationStringArray in
      api.swiftscan_scan_invocation_set_argv(invocationRef,
                                             Int32(invocationCommand.count),
                                             invocationStringArray)
    }

    // Create and populate a batch scan input `swiftscan_batch_scan_input_t`
    let moduleEntriesPtr =
      UnsafeMutablePointer<swiftscan_batch_scan_entry_t?>.allocate(capacity: batchInfos.count)
    for (index, batchEntryInfo) in batchInfos.enumerated() {
      // Create and populate an individual `swiftscan_batch_scan_entry_t`
      let entryRef = api.swiftscan_batch_scan_entry_create()
      switch batchEntryInfo {
        case .clang(let clangEntryInfo):
          api.swiftscan_batch_scan_entry_set_module_name(entryRef,
                                                     clangEntryInfo.clangModuleName
                                                      .cString(using: String.Encoding.utf8))
          api.swiftscan_batch_scan_entry_set_is_swift(entryRef, false)
          api.swiftscan_batch_scan_entry_set_arguments(entryRef, clangEntryInfo.arguments
                                                        .cString(using: String.Encoding.utf8))
        case .swift(let swiftEntryInfo):
          api.swiftscan_batch_scan_entry_set_module_name(entryRef,
                                                         swiftEntryInfo.swiftModuleName
                                                          .cString(using: String.Encoding.utf8))
          api.swiftscan_batch_scan_entry_set_is_swift(entryRef, true)
      }
      (moduleEntriesPtr + index).initialize(to: entryRef)
    }
    let inputRef = api.swiftscan_batch_scan_input_create()
    // Disposing of the input frees memory of the contained entries, as well.
    defer { api.swiftscan_batch_scan_input_dispose(inputRef) }
    api.swiftscan_batch_scan_input_set_modules(inputRef, Int32(batchInfos.count),
                                               moduleEntriesPtr)

    let batchResultRefOrNull = api.swiftscan_batch_scan_result_create(scanner,
                                                                      inputRef,
                                                                      invocationRef)
    guard let batchResultRef = batchResultRefOrNull else {
      throw DependencyScanningError.dependencyScanFailed
    }
    // Translate `swiftscan_batch_scan_result_t`
    // into `[ModuleDependencyId: [InterModuleDependencyGraph]]`
    let resultGraphMap = try constructBatchResultGraphs(for: batchInfos,
                                                        moduleAliases:  moduleAliases,
                                                        from: batchResultRef.pointee)
    // Free the memory allocated for the in-memory representation of the batch scan
    // result, now that we have translated it.
    api.swiftscan_batch_scan_result_dispose(batchResultRefOrNull)
    return resultGraphMap
  }

  @_spi(Testing) public var hasBinarySwiftModuleIsFramework : Bool {
    api.swiftscan_swift_binary_detail_get_is_framework != nil
  }

  @_spi(Testing) public var canLoadStoreScannerCache : Bool {
    api.swiftscan_scanner_cache_load != nil &&
    api.swiftscan_scanner_cache_serialize != nil &&
    api.swiftscan_scanner_cache_reset != nil
  }

  @_spi(Testing) public var clangDetailsHaveCapturedPCMArgs : Bool {
    api.swiftscan_clang_detail_get_captured_pcm_args != nil
  }

  @_spi(Testing) public var supportsBinaryModuleHeaderDependencies : Bool {
    return api.swiftscan_swift_binary_detail_get_header_dependencies != nil
  }

  @_spi(Testing) public var supportsStringDispose : Bool {
    return api.swiftscan_string_dispose != nil
  }


  @_spi(Testing) public var supportsSeparateSwiftOverlayDependencies : Bool {
    return api.swiftscan_swift_textual_detail_get_swift_overlay_dependencies != nil
  }

  @_spi(Testing) public var supportsScannerDiagnostics : Bool {
    return api.swiftscan_scanner_diagnostics_query != nil &&
           api.swiftscan_scanner_diagnostics_reset != nil &&
           api.swiftscan_diagnostic_get_message != nil &&
           api.swiftscan_diagnostic_get_severity != nil &&
           api.swiftscan_diagnostics_set_dispose != nil
  }

  @_spi(Testing) public var supportsCaching : Bool {
#if os(Windows)
    // Caching is currently not supported on Windows hosts.
    return false
#else
    return api.swiftscan_cas_options_create != nil &&
           api.swiftscan_cas_options_dispose != nil &&
           api.swiftscan_cas_options_set_ondisk_path != nil &&
           api.swiftscan_cas_options_set_plugin_path != nil &&
           api.swiftscan_cas_options_set_option != nil &&
           api.swiftscan_cas_create_from_options != nil &&
           api.swiftscan_cas_dispose != nil &&
           api.swiftscan_compute_cache_key != nil &&
           api.swiftscan_cas_store != nil &&
           api.swiftscan_swift_textual_detail_get_module_cache_key != nil &&
           api.swiftscan_swift_binary_detail_get_module_cache_key != nil &&
           api.swiftscan_clang_detail_get_module_cache_key != nil
#endif
  }

  @_spi(Testing) public var supportsBridgingHeaderPCHCommand : Bool {
    return api.swiftscan_swift_textual_detail_get_bridging_pch_command_line != nil
  }

  func serializeScannerCache(to path: AbsolutePath) {
    api.swiftscan_scanner_cache_serialize(scanner,
                                          path.description.cString(using: String.Encoding.utf8))
  }

  func loadScannerCache(from path: AbsolutePath) -> Bool {
    return api.swiftscan_scanner_cache_load(scanner,
                                            path.description.cString(using: String.Encoding.utf8))
  }

  func resetScannerCache() {
    api.swiftscan_scanner_cache_reset(scanner)
  }

  @_spi(Testing) public func queryScannerDiagnostics() throws -> [ScannerDiagnosticPayload] {
    var result: [ScannerDiagnosticPayload] = []
    let diagnosticSetRefOrNull = api.swiftscan_scanner_diagnostics_query(scanner)
    guard let diagnosticSetRef = diagnosticSetRefOrNull else {
      // Seems heavy-handed to fail here
      // throw DependencyScanningError.dependencyScanFailed
      return []
    }
    defer { api.swiftscan_diagnostics_set_dispose(diagnosticSetRef) }
    let diagnosticRefArray = Array(UnsafeBufferPointer(start: diagnosticSetRef.pointee.diagnostics,
                                                       count: Int(diagnosticSetRef.pointee.count)))

    for diagnosticRefOrNull in diagnosticRefArray {
      guard let diagnosticRef = diagnosticRefOrNull else {
        throw DependencyScanningError.dependencyScanFailed
      }
      let message = try toSwiftString(api.swiftscan_diagnostic_get_message(diagnosticRef))
      let severity = api.swiftscan_diagnostic_get_severity(diagnosticRef)
      result.append(ScannerDiagnosticPayload(severity: severity.toDiagnosticBehavior(), message: message))
    }
    return result
  }

  @_spi(Testing) public func resetScannerDiagnostics() throws {
    api.swiftscan_scanner_diagnostics_reset(scanner)
  }

  @_spi(Testing) public func canQuerySupportedArguments() -> Bool {
    return api.swiftscan_compiler_supported_arguments_query != nil &&
           api.swiftscan_string_set_dispose != nil
  }

  @_spi(Testing) public func querySupportedArguments() throws -> Set<String> {
    precondition(canQuerySupportedArguments())
    if let queryResultStrings = api.swiftscan_compiler_supported_arguments_query!() {
      defer { api.swiftscan_string_set_dispose!(queryResultStrings) }
      return try toSwiftStringSet(queryResultStrings.pointee)
    } else {
      throw DependencyScanningError.argumentQueryFailed
    }
  }

  @_spi(Testing) public func canQueryTargetInfo() -> Bool {
    return api.swiftscan_compiler_target_info_query_v2 != nil &&
           api.swiftscan_string_set_dispose != nil
  }

  func queryTargetInfoJSON(workingDirectory: AbsolutePath,
                           compilerExecutablePath: AbsolutePath,
                           invocationCommand: [String]) throws -> Data {
    // Create and configure the scanner invocation
    let invocation = api.swiftscan_scan_invocation_create()
    defer { api.swiftscan_scan_invocation_dispose(invocation) }
    api.swiftscan_scan_invocation_set_working_directory(invocation,
                                                        workingDirectory
                                                          .description
                                                          .cString(using: String.Encoding.utf8))
    withArrayOfCStrings(invocationCommand) { invocationStringArray in
      api.swiftscan_scan_invocation_set_argv(invocation,
                                             Int32(invocationCommand.count),
                                             invocationStringArray)
    }

    return try compilerExecutablePath.description.withCString {
      let info = api.swiftscan_compiler_target_info_query_v2(invocation, $0)
      defer { api.swiftscan_string_dispose(info) }
      guard let data = info.data else {
        throw DependencyScanningError.invalidStringPtr
      }
      return Data(buffer: UnsafeBufferPointer(start: data.bindMemory(to: CChar.self, capacity: info.length),
                                              count: info.length))
    }
  }

  private func handleCASError(_ closure: (inout swiftscan_string_ref_t) -> Bool) throws {
    var err_msg : swiftscan_string_ref_t = swiftscan_string_ref_t()
    guard !closure(&err_msg) else {
      let err_str = try toSwiftString(err_msg)
      api.swiftscan_string_dispose(err_msg)
      throw DependencyScanningError.casError(err_str)
    }
  }

  func createCAS(pluginPath: String?, onDiskPath: String?, pluginOptions: [(String, String)]) throws {
    let casOpts = api.swiftscan_cas_options_create()
    defer {
      api.swiftscan_cas_options_dispose(casOpts)
    }
    if let path = pluginPath {
      api.swiftscan_cas_options_set_plugin_path(casOpts, path)
    }
    if let path = onDiskPath {
      api.swiftscan_cas_options_set_ondisk_path(casOpts, path)
    }
    for (name, value) in pluginOptions {
      try handleCASError { err_msg in
        return api.swiftscan_cas_options_set_option(casOpts, name, value, &err_msg)
      }
    }
    try handleCASError { err_msg in
      self.cas = api.swiftscan_cas_create_from_options(casOpts, &err_msg)
      return self.cas == nil
    }
  }

  func store(data: Data) throws -> String {
    guard let scan_cas = self.cas else {
      throw DependencyScanningError.casError("cannot store into CAS because CAS is not yet created")
    }
    let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
    data.copyBytes(to: bytes, count: data.count)
    var casid: swiftscan_string_ref_t = swiftscan_string_ref_t()
    try handleCASError { err_msg in
      casid = api.swiftscan_cas_store(scan_cas, bytes, UInt32(data.count), &err_msg)
      return casid.data == nil
    }
    return try toSwiftString(casid)
  }

  private func getSwiftScanOutputKind(kind: FileType) -> swiftscan_output_kind_t {
    switch (kind) {
      case .object:
        return SWIFTSCAN_OUTPUT_TYPE_OBJECT
      case .swiftModule:
        return SWIFTSCAN_OUTPUT_TYPE_SWIFTMODULE
      case .swiftInterface:
        return SWIFTSCAN_OUTPUT_TYPE_SWIFTINTERFACE
      case .privateSwiftInterface:
        return SWIFTSCAN_OUTPUT_TYPE_SWIFTPRIVATEINTERFACE
      case .pcm:
        return SWIFTSCAN_OUTPUT_TYPE_CLANG_MODULE
      case .pch:
        return SWIFTSCAN_OUTPUT_TYPE_CLANG_PCH
      default:
        fatalError("Unsupported")
    }
  }

  func computeCacheKeyForOutput(kind: FileType, commandLine: [String], input: String) throws -> String {
    guard let scan_cas = self.cas else {
      throw DependencyScanningError.casError("cannot compute CacheKey for compilation because CAS is not yet created")
    }
    var casid: swiftscan_string_ref_t = swiftscan_string_ref_t()
    try handleCASError { err_msg in
      withArrayOfCStrings(commandLine) { commandArray in
        casid = api.swiftscan_compute_cache_key(scan_cas,
                                                Int32(commandLine.count),
                                                commandArray,
                                                input.cString(using: String.Encoding.utf8),
                                                getSwiftScanOutputKind(kind: kind),
                                                &err_msg)
      }
      return casid.data == nil
    }
    return try toSwiftString(casid)
  }
}

// Used for testing purposes only
@_spi(Testing) public extension Driver {
  func querySupportedArgumentsForTest() throws -> Set<String>? {
    // If a capable libSwiftScan is found, manually ensure we can get the supported arguments
    if let scanLibPath = try toolchain.lookupSwiftScanLib() {
      let libSwiftScanInstance = try SwiftScan(dylib: scanLibPath)
      if libSwiftScanInstance.canQuerySupportedArguments() {
        return try libSwiftScanInstance.querySupportedArguments()
      }
    }
    return nil
  }
}

private extension swiftscan_functions_t {
  init(_ swiftscan: Loader.Handle) throws {
    self.init()

    // MARK: Optional Methods
    // Future optional methods can be queried here
    func loadOptional<T>(_ symbol: String) throws -> T? {
      guard let sym: T = Loader.lookup(symbol: symbol, in: swiftscan) else {
        return nil
      }
      return sym
    }
    // Supported features/flags query
    self.swiftscan_string_set_dispose =
      try loadOptional("swiftscan_string_set_dispose")
    self.swiftscan_compiler_supported_arguments_query =
      try loadOptional("swiftscan_compiler_supported_arguments_query")
    self.swiftscan_compiler_supported_features_query =
      try loadOptional("swiftscan_compiler_supported_features_query")

    // Target Info query
    self.swiftscan_compiler_target_info_query_v2 =
      try loadOptional("swiftscan_compiler_target_info_query_v2")

    // Dependency scanner serialization/deserialization features
    self.swiftscan_scanner_cache_serialize =
      try loadOptional("swiftscan_scanner_cache_serialize")
    self.swiftscan_scanner_cache_load =
      try loadOptional("swiftscan_scanner_cache_load")
    self.swiftscan_scanner_cache_reset =
      try loadOptional("swiftscan_scanner_cache_reset")

    // Clang dependency captured PCM args
    self.swiftscan_clang_detail_get_captured_pcm_args =
      try loadOptional("swiftscan_clang_detail_get_captured_pcm_args")

    // Scanner diagnostic emission query
    self.swiftscan_scanner_diagnostics_query =
      try loadOptional("swiftscan_scanner_diagnostics_query")
    self.swiftscan_scanner_diagnostics_reset =
      try loadOptional("swiftscan_scanner_diagnostics_reset")
    self.swiftscan_diagnostic_get_message =
      try loadOptional("swiftscan_diagnostic_get_message")
    self.swiftscan_diagnostic_get_severity =
      try loadOptional("swiftscan_diagnostic_get_severity")
    self.swiftscan_diagnostics_set_dispose =
      try loadOptional("swiftscan_diagnostics_set_dispose")
    self.swiftscan_string_dispose =
      try loadOptional("swiftscan_string_dispose")

    // isFramework on binary module dependencies
    self.swiftscan_swift_binary_detail_get_is_framework =
      try loadOptional("swiftscan_swift_binary_detail_get_is_framework")

    self.swiftscan_swift_textual_detail_get_bridging_pch_command_line =
      try loadOptional("swiftscan_swift_textual_detail_get_bridging_pch_command_line")

    // Caching related APIs.
    self.swiftscan_swift_textual_detail_get_module_cache_key =
      try loadOptional("swiftscan_swift_textual_detail_get_module_cache_key")
    self.swiftscan_swift_binary_detail_get_module_cache_key =
      try loadOptional("swiftscan_swift_binary_detail_get_module_cache_key")
    self.swiftscan_clang_detail_get_module_cache_key =
      try loadOptional("swiftscan_clang_detail_get_module_cache_key")

    self.swiftscan_cas_options_create = try loadOptional("swiftscan_cas_options_create")
    self.swiftscan_cas_options_set_plugin_path = try loadOptional("swiftscan_cas_options_set_plugin_path")
    self.swiftscan_cas_options_set_ondisk_path = try loadOptional("swiftscan_cas_options_set_ondisk_path")
    self.swiftscan_cas_options_set_option = try loadOptional("swiftscan_cas_options_set_option")
    self.swiftscan_cas_options_dispose = try loadOptional("swiftscan_cas_options_dispose")
    self.swiftscan_cas_create_from_options = try loadOptional("swiftscan_cas_create_from_options")
    self.swiftscan_cas_dispose = try loadOptional("swiftscan_cas_dispose")
    self.swiftscan_compute_cache_key =
      try loadOptional("swiftscan_compute_cache_key")
    self.swiftscan_cas_store = try loadOptional("swiftscan_cas_store")


    // Swift Overlay Dependencies
    self.swiftscan_swift_textual_detail_get_swift_overlay_dependencies =
      try loadOptional("swiftscan_swift_textual_detail_get_swift_overlay_dependencies")

    // Header dependencies of binary modules
    self.swiftscan_swift_binary_detail_get_header_dependencies =
      try loadOptional("swiftscan_swift_binary_detail_get_header_dependencies")

    // MARK: Required Methods
    func loadRequired<T>(_ symbol: String) throws -> T {
      guard let sym: T = Loader.lookup(symbol: symbol, in: swiftscan) else {
        throw DependencyScanningError.missingRequiredSymbol(symbol)
      }
      return sym
    }

    self.swiftscan_scanner_create =
      try loadRequired("swiftscan_scanner_create")
    self.swiftscan_scanner_dispose =
      try loadRequired("swiftscan_scanner_dispose")
    self.swiftscan_scan_invocation_get_working_directory =
      try loadRequired("swiftscan_scan_invocation_get_working_directory")
    self.swiftscan_scan_invocation_set_argv =
      try loadRequired("swiftscan_scan_invocation_set_argv")
    self.swiftscan_scan_invocation_set_working_directory =
      try loadRequired("swiftscan_scan_invocation_set_working_directory")
    self.swiftscan_scan_invocation_create =
      try loadRequired("swiftscan_scan_invocation_create")
    self.swiftscan_import_set_get_imports =
      try loadRequired("swiftscan_import_set_get_imports")
    self.swiftscan_batch_scan_entry_create =
      try loadRequired("swiftscan_batch_scan_entry_create")
    self.swiftscan_batch_scan_entry_get_is_swift =
      try loadRequired("swiftscan_batch_scan_entry_get_is_swift")
    self.swiftscan_batch_scan_entry_get_arguments =
      try loadRequired("swiftscan_batch_scan_entry_get_arguments")
    self.swiftscan_batch_scan_entry_get_module_name =
      try loadRequired("swiftscan_batch_scan_entry_get_module_name")
    self.swiftscan_batch_scan_entry_set_is_swift =
      try loadRequired("swiftscan_batch_scan_entry_set_is_swift")
    self.swiftscan_batch_scan_entry_set_arguments =
      try loadRequired("swiftscan_batch_scan_entry_set_arguments")
    self.swiftscan_batch_scan_entry_set_module_name =
      try loadRequired("swiftscan_batch_scan_entry_set_module_name")
    self.swiftscan_batch_scan_input_set_modules =
      try loadRequired("swiftscan_batch_scan_input_set_modules")
    self.swiftscan_batch_scan_input_create =
      try loadRequired("swiftscan_batch_scan_input_create")
    self.swiftscan_clang_detail_get_command_line =
      try loadRequired("swiftscan_clang_detail_get_command_line")
    self.swiftscan_clang_detail_get_context_hash =
      try loadRequired("swiftscan_clang_detail_get_context_hash")
    self.swiftscan_clang_detail_get_module_map_path =
      try loadRequired("swiftscan_clang_detail_get_module_map_path")
    self.swiftscan_swift_placeholder_detail_get_module_source_info_path =
      try loadRequired("swiftscan_swift_placeholder_detail_get_module_source_info_path")
    self.swiftscan_swift_placeholder_detail_get_module_doc_path =
      try loadRequired("swiftscan_swift_placeholder_detail_get_module_doc_path")
    self.swiftscan_swift_placeholder_detail_get_compiled_module_path =
      try loadRequired("swiftscan_swift_placeholder_detail_get_compiled_module_path")
    self.swiftscan_swift_binary_detail_get_module_source_info_path =
      try loadRequired("swiftscan_swift_binary_detail_get_module_source_info_path")
    self.swiftscan_swift_binary_detail_get_module_doc_path =
      try loadRequired("swiftscan_swift_binary_detail_get_module_doc_path")
    self.swiftscan_swift_binary_detail_get_compiled_module_path =
      try loadRequired("swiftscan_swift_binary_detail_get_compiled_module_path")
    self.swiftscan_swift_textual_detail_get_is_framework =
      try loadRequired("swiftscan_swift_textual_detail_get_is_framework")
    self.swiftscan_swift_textual_detail_get_context_hash =
      try loadRequired("swiftscan_swift_textual_detail_get_context_hash")
    self.swiftscan_dependency_graph_get_main_module_name =
      try loadRequired("swiftscan_dependency_graph_get_main_module_name")
    self.swiftscan_dependency_graph_get_dependencies =
      try loadRequired("swiftscan_dependency_graph_get_dependencies")
    self.swiftscan_module_info_get_module_name =
      try loadRequired("swiftscan_module_info_get_module_name")
    self.swiftscan_module_info_get_module_path =
      try loadRequired("swiftscan_module_info_get_module_path")
    self.swiftscan_module_info_get_source_files =
      try loadRequired("swiftscan_module_info_get_source_files")
    self.swiftscan_module_info_get_direct_dependencies =
      try loadRequired("swiftscan_module_info_get_direct_dependencies")
    self.swiftscan_module_info_get_details =
      try loadRequired("swiftscan_module_info_get_details")
    self.swiftscan_module_detail_get_kind =
      try loadRequired("swiftscan_module_detail_get_kind")
    self.swiftscan_swift_textual_detail_get_module_interface_path =
      try loadRequired("swiftscan_swift_textual_detail_get_module_interface_path")
    self.swiftscan_swift_textual_detail_get_compiled_module_candidates =
      try loadRequired("swiftscan_swift_textual_detail_get_compiled_module_candidates")
    self.swiftscan_swift_textual_detail_get_bridging_header_path =
      try loadRequired("swiftscan_swift_textual_detail_get_bridging_header_path")
    self.swiftscan_swift_textual_detail_get_bridging_source_files =
      try loadRequired("swiftscan_swift_textual_detail_get_bridging_source_files")
    self.swiftscan_swift_textual_detail_get_bridging_module_dependencies =
      try loadRequired("swiftscan_swift_textual_detail_get_bridging_module_dependencies")
    self.swiftscan_swift_textual_detail_get_command_line =
      try loadRequired("swiftscan_swift_textual_detail_get_command_line")
    self.swiftscan_swift_textual_detail_get_extra_pcm_args =
      try loadRequired("swiftscan_swift_textual_detail_get_extra_pcm_args")
    self.swiftscan_scan_invocation_get_argc =
      try loadRequired("swiftscan_scan_invocation_get_argc")
    self.swiftscan_scan_invocation_get_argv =
      try loadRequired("swiftscan_scan_invocation_get_argv")
    self.swiftscan_dependency_graph_dispose =
      try loadRequired("swiftscan_dependency_graph_dispose")
    self.swiftscan_import_set_dispose =
      try loadRequired("swiftscan_import_set_dispose")
    self.swiftscan_batch_scan_entry_dispose =
      try loadRequired("swiftscan_batch_scan_entry_dispose")
    self.swiftscan_batch_scan_input_dispose =
      try loadRequired("swiftscan_batch_scan_input_dispose")
    self.swiftscan_batch_scan_result_dispose =
      try loadRequired("swiftscan_batch_scan_result_dispose")
    self.swiftscan_scan_invocation_dispose =
      try loadRequired("swiftscan_scan_invocation_dispose")
    self.swiftscan_dependency_graph_create =
      try loadRequired("swiftscan_dependency_graph_create")
    self.swiftscan_batch_scan_result_create =
      try loadRequired("swiftscan_batch_scan_result_create")
    self.swiftscan_import_set_create =
      try loadRequired("swiftscan_import_set_create")
  }
}

// TODO: Move to TSC?
/// Perform an  `action` passing it a `const char **` constructed out of `[String]`
func withArrayOfCStrings(_ strings: [String],
                         _ action:  (UnsafeMutablePointer<UnsafePointer<Int8>?>?) -> Void)
{
  let cstrings = strings.map { strdup($0) } + [nil]
  let unsafeCStrings = cstrings.map { UnsafePointer($0) }
  let _ = unsafeCStrings.withUnsafeBufferPointer {
    action(UnsafeMutablePointer(mutating: $0.baseAddress))
  }
  for ptr in cstrings { if let ptr = ptr { free(ptr) } }
}
