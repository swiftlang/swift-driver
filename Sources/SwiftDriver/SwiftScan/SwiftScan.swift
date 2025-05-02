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

#if os(Windows)
import CRT
#endif

import func Foundation.strdup
import func Foundation.free
import class Foundation.JSONDecoder
import protocol Foundation.LocalizedError
import struct Foundation.Data

import protocol TSCBasic.DiagnosticData
import struct TSCBasic.AbsolutePath
import struct TSCBasic.Diagnostic
import protocol TSCBasic.DiagnosticLocation

public enum DependencyScanningError: LocalizedError, DiagnosticData, Equatable {
  case missingRequiredSymbol(String)
  case dependencyScanFailed(String)
  case failedToInstantiateScanner
  case casError(String)
  case missingField(String)
  case moduleNameDecodeFailure(String)
  case unsupportedDependencyDetailsKind(Int)
  case invalidStringPtr
  case scanningLibraryInvocationMismatch(String, String)
  case scanningLibraryNotFound(AbsolutePath)
  case argumentQueryFailed

  public var description: String {
    switch self {
      case .missingRequiredSymbol(let symbolName):
        return "libSwiftScan missing required symbol: '\(symbolName)'"
      case .dependencyScanFailed(let reason):
        return "Dependency scan query failed: `\(reason)`"
      case .failedToInstantiateScanner:
        return "Failed to create scanner instance"
      case .casError(let reason):
        return "CAS error: \(reason)"
      case .missingField(let fieldName):
        return "Scan result missing required field: `\(fieldName)`"
      case .moduleNameDecodeFailure(let encodedName):
        return "Failed to decode dependency module name: `\(encodedName)`"
      case .unsupportedDependencyDetailsKind(let kindRawValue):
        return "Dependency module details field kind not supported: `\(kindRawValue)`"
      case .invalidStringPtr:
        return "Dependency module details contains a corrupted string reference"
      case .scanningLibraryInvocationMismatch(let path1, let path2):
        return "Dependency Scanning library differs across driver invocations: \(path1) and \(path2)"
      case .scanningLibraryNotFound(let path):
        return "Dependency Scanning library not found at path: \(path)"
      case .argumentQueryFailed:
        return "Supported compiler argument query failed"
    }
  }

  public var errorDescription: String? {
    return self.description
  }
}

public struct ScannerDiagnosticSourceLocation : DiagnosticLocation {
  public var description: String {
    return "\(bufferIdentifier):\(lineNumber):\(columnNumber)"
  }
  public let bufferIdentifier: String
  public let lineNumber: Int
  public let columnNumber: Int
}

public struct ScannerDiagnosticPayload {
  public let severity: Diagnostic.Behavior
  public let message: String
  public let sourceLocation: ScannerDiagnosticSourceLocation?
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

private extension String {
  func stripNewline() -> String {
    return self.hasSuffix("\n") ? String(self.dropLast()) : self
  }
}

/// Wrapper for libSwiftScan, taking care of initialization, shutdown, and dispatching dependency scanning queries.
@_spi(Testing) public final class SwiftScan {
  /// The path to the libSwiftScan dylib.
  let path: AbsolutePath?

  /// The handle to the dylib.
  let dylib: Loader.Handle

  /// libSwiftScan API functions.
  let api: swiftscan_functions_t;

  /// Instance of a scanner, which maintains shared state across scan queries.
  let scanner: swiftscan_scanner_t;

  @_spi(Testing) public init(dylib path: AbsolutePath? = nil) throws {
    self.path = path
    if let externalPath = path {
#if os(Windows)
      self.dylib = try Loader.load(externalPath.pathString, mode: [])
#else
      self.dylib = try Loader.load(externalPath.pathString, mode: [.lazy, .local, .first])
#endif
    } else {
#if os(Windows)
      self.dylib = try Loader.getSelfHandle(mode: [])
#else
      self.dylib = try Loader.getSelfHandle(mode: [.lazy, .local, .first])
#endif
    }
    self.api = try swiftscan_functions_t(self.dylib)
    guard let scanner = api.swiftscan_scanner_create() else {
      throw DependencyScanningError.failedToInstantiateScanner
    }
    self.scanner = scanner
  }

  deinit {
    api.swiftscan_scanner_dispose(self.scanner)
    // FIXME: is it safe to dlclose() swiftscan? If so, do that here.
    // For now, let the handle leak.
    dylib.leak()
  }

  func preScanImports(workingDirectory: AbsolutePath,
                      moduleAliases: [String: String]?,
                      invocationCommand: [String],
                      diagnostics: inout [ScannerDiagnosticPayload]) throws -> InterModuleDependencyImports {
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
      throw DependencyScanningError.dependencyScanFailed("Unable to produce import set")
    }
    defer { api.swiftscan_import_set_dispose(importSetRef) }

    if canQueryPerScanDiagnostics {
      let diagnosticsSetRefOrNull = api.swiftscan_import_set_get_diagnostics(importSetRef)
      guard let diagnosticsSetRef = diagnosticsSetRefOrNull else {
        throw DependencyScanningError.dependencyScanFailed("Unable to query dependency diagnostics")
      }
      diagnostics = try mapToDriverDiagnosticPayload(diagnosticsSetRef)
    }

    return try constructImportSet(from: importSetRef, with: moduleAliases)
  }

  func scanDependencies(workingDirectory: AbsolutePath,
                        moduleAliases: [String: String]?,
                        invocationCommand: [String],
                        diagnostics: inout [ScannerDiagnosticPayload]) throws -> InterModuleDependencyGraph {
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
      throw DependencyScanningError.dependencyScanFailed("Unable to produce dependency graph")
    }
    defer { api.swiftscan_dependency_graph_dispose(graphRef) }

    if canQueryPerScanDiagnostics {
      let diagnosticsSetRefOrNull = api.swiftscan_dependency_graph_get_diagnostics(graphRef)
      guard let diagnosticsSetRef = diagnosticsSetRefOrNull else {
        throw DependencyScanningError.dependencyScanFailed("Unable to query dependency diagnostics")
      }
      diagnostics = try mapToDriverDiagnosticPayload(diagnosticsSetRef)
    }

    return try constructGraph(from: graphRef, moduleAliases: moduleAliases)
  }

  @_spi(Testing) public var hasBinarySwiftModuleIsFramework : Bool {
    api.swiftscan_swift_binary_detail_get_is_framework != nil
  }

  @_spi(Testing) public var hasBinarySwiftModuleHeaderModuleDependencies : Bool {
    api.swiftscan_swift_binary_detail_get_header_dependency_module_dependencies != nil
  }

  @_spi(Testing) public var supportsBinaryModuleHeaderDependencies : Bool {
    return api.swiftscan_swift_binary_detail_get_header_dependencies != nil
  }

  @_spi(Testing) public var supportsBinaryModuleHeaderDependency : Bool {
    return api.swiftscan_swift_binary_detail_get_header_dependency != nil
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
           api.swiftscan_cas_options_set_plugin_option != nil &&
           api.swiftscan_cas_create_from_options != nil &&
           api.swiftscan_cas_dispose != nil &&
           api.swiftscan_cache_compute_key != nil &&
           api.swiftscan_cache_compute_key_from_input_index != nil &&
           api.swiftscan_cas_store != nil &&
           api.swiftscan_swift_textual_detail_get_module_cache_key != nil &&
           api.swiftscan_swift_binary_detail_get_module_cache_key != nil &&
           api.swiftscan_clang_detail_get_module_cache_key != nil
#endif
  }

  @_spi(Testing) public var supportsCASSizeManagement : Bool {
#if os(Windows)
    // CAS is currently not supported on Windows hosts.
    return false
#else
    return api.swiftscan_cas_get_ondisk_size != nil &&
           api.swiftscan_cas_set_ondisk_size_limit != nil &&
           api.swiftscan_cas_prune_ondisk_data != nil
#endif
  }

  @_spi(Testing) public var supportsBridgingHeaderPCHCommand : Bool {
    return api.swiftscan_swift_textual_detail_get_bridging_pch_command_line != nil
  }

  @_spi(Testing) public var supportsChainedBridgingHeader : Bool {
    return api.swiftscan_swift_textual_detail_get_chained_bridging_header_path != nil &&
           api.swiftscan_swift_textual_detail_get_chained_bridging_header_content != nil
  }

  @_spi(Testing) public var canQueryPerScanDiagnostics : Bool {
    return api.swiftscan_dependency_graph_get_diagnostics != nil &&
           api.swiftscan_import_set_get_diagnostics != nil
  }

  @_spi(Testing) public var supportsDiagnosticSourceLocations : Bool {
    return api.swiftscan_diagnostic_get_source_location != nil &&
           api.swiftscan_source_location_get_buffer_identifier != nil &&
           api.swiftscan_source_location_get_line_number != nil &&
           api.swiftscan_source_location_get_column_number != nil
  }

  @_spi(Testing) public var supportsLinkLibraries : Bool {
    return api.swiftscan_module_info_get_link_libraries != nil &&
           api.swiftscan_link_library_info_get_link_name != nil &&
           api.swiftscan_link_library_info_get_is_framework != nil &&
           api.swiftscan_link_library_info_get_should_force_load != nil
  }

  internal func mapToDriverDiagnosticPayload(_ diagnosticSetRef: UnsafeMutablePointer<swiftscan_diagnostic_set_t>) throws -> [ScannerDiagnosticPayload] {
    var result: [ScannerDiagnosticPayload] = []
    let diagnosticRefArray = Array(UnsafeBufferPointer(start: diagnosticSetRef.pointee.diagnostics,
                                                       count: Int(diagnosticSetRef.pointee.count)))
    for diagnosticRefOrNull in diagnosticRefArray {
      guard let diagnosticRef = diagnosticRefOrNull else {
        throw DependencyScanningError.dependencyScanFailed("Unable to produce scanner diagnostics")
      }
      let message = try toSwiftString(api.swiftscan_diagnostic_get_message(diagnosticRef)).stripNewline()
      let severity = api.swiftscan_diagnostic_get_severity(diagnosticRef)

      var sourceLoc: ScannerDiagnosticSourceLocation? = nil
      if supportsDiagnosticSourceLocations {
        let sourceLocRefOrNull = api.swiftscan_diagnostic_get_source_location(diagnosticRef)
        if let sourceLocRef = sourceLocRefOrNull {
          let bufferName = try toSwiftString(api.swiftscan_source_location_get_buffer_identifier(sourceLocRef))
          let lineNumber = api.swiftscan_source_location_get_line_number(sourceLocRef)
          let columnNumber = api.swiftscan_source_location_get_column_number(sourceLocRef)
          sourceLoc = ScannerDiagnosticSourceLocation(bufferIdentifier: bufferName,
                                                      lineNumber: Int(lineNumber),
                                                      columnNumber: Int(columnNumber))
        }
      }
      result.append(ScannerDiagnosticPayload(severity: severity.toDiagnosticBehavior(),
                                             message: message,
                                             sourceLocation: sourceLoc))
    }
    return result
  }

  @_spi(Testing) public func queryScannerDiagnostics() throws -> [ScannerDiagnosticPayload] {
    let diagnosticSetRefOrNull = api.swiftscan_scanner_diagnostics_query(scanner)
    guard let diagnosticSetRef = diagnosticSetRefOrNull else {
      // Seems heavy-handed to fail here
      // throw DependencyScanningError.dependencyScanFailed
      return []
    }
    defer { api.swiftscan_diagnostics_set_dispose(diagnosticSetRef) }
    return try mapToDriverDiagnosticPayload(diagnosticSetRef)
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

  func handleCASError<T>(_ closure: (inout swiftscan_string_ref_t) -> T) throws -> T{
    var err_msg : swiftscan_string_ref_t = swiftscan_string_ref_t()
    let ret = closure(&err_msg)
    if err_msg.length != 0 {
      let err_str = try toSwiftString(err_msg)
      api.swiftscan_string_dispose(err_msg)
      throw DependencyScanningError.casError(err_str)
    }
    return ret
  }

  func createCAS(pluginPath: String?, onDiskPath: String?, pluginOptions: [(String, String)]) throws -> SwiftScanCAS {
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
        _ = api.swiftscan_cas_options_set_plugin_option(casOpts, name, value, &err_msg)
      }
    }
    let cas = try handleCASError { err_msg in
      api.swiftscan_cas_create_from_options(casOpts, &err_msg)
    }
    return SwiftScanCAS(cas: cas!, scanner: self)
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
    func loadOptional<T>(_ symbol: String) -> T? {
      guard let sym: T = Loader.lookup(symbol: symbol, in: swiftscan) else {
        return nil
      }
      return sym
    }
    // Supported features/flags query
    self.swiftscan_string_set_dispose =
      loadOptional("swiftscan_string_set_dispose")
    self.swiftscan_compiler_supported_arguments_query =
      loadOptional("swiftscan_compiler_supported_arguments_query")
    self.swiftscan_compiler_supported_features_query =
      loadOptional("swiftscan_compiler_supported_features_query")

    // Target Info query
    self.swiftscan_compiler_target_info_query_v2 =
      loadOptional("swiftscan_compiler_target_info_query_v2")

    // Scanner diagnostic emission query
    self.swiftscan_scanner_diagnostics_query =
      loadOptional("swiftscan_scanner_diagnostics_query")
    self.swiftscan_scanner_diagnostics_reset =
      loadOptional("swiftscan_scanner_diagnostics_reset")
    self.swiftscan_diagnostic_get_message =
      loadOptional("swiftscan_diagnostic_get_message")
    self.swiftscan_diagnostic_get_severity =
      loadOptional("swiftscan_diagnostic_get_severity")
    self.swiftscan_diagnostics_set_dispose =
      loadOptional("swiftscan_diagnostics_set_dispose")
    self.swiftscan_string_dispose =
      loadOptional("swiftscan_string_dispose")

    // isFramework on binary module dependencies
    self.swiftscan_swift_binary_detail_get_is_framework =
      loadOptional("swiftscan_swift_binary_detail_get_is_framework")

    // Clang module dependencies of header input of binary module dependencies
    self.swiftscan_swift_binary_detail_get_header_dependency_module_dependencies =
      loadOptional("swiftscan_swift_binary_detail_get_header_dependency_module_dependencies")

    // Bridging PCH build command-line
    self.swiftscan_swift_textual_detail_get_bridging_pch_command_line =
      loadOptional("swiftscan_swift_textual_detail_get_bridging_pch_command_line")
    self.swiftscan_swift_textual_detail_get_chained_bridging_header_path =
      loadOptional("swiftscan_swift_textual_detail_get_chained_bridging_header_path")
    self.swiftscan_swift_textual_detail_get_chained_bridging_header_content =
      loadOptional("swiftscan_swift_textual_detail_get_chained_bridging_header_content")

    // Caching related APIs.
    self.swiftscan_swift_textual_detail_get_module_cache_key =
      loadOptional("swiftscan_swift_textual_detail_get_module_cache_key")
    self.swiftscan_swift_binary_detail_get_module_cache_key =
      loadOptional("swiftscan_swift_binary_detail_get_module_cache_key")
    self.swiftscan_clang_detail_get_module_cache_key =
      loadOptional("swiftscan_clang_detail_get_module_cache_key")

    self.swiftscan_cas_options_create = loadOptional("swiftscan_cas_options_create")
    self.swiftscan_cas_options_set_plugin_path = loadOptional("swiftscan_cas_options_set_plugin_path")
    self.swiftscan_cas_options_set_ondisk_path = loadOptional("swiftscan_cas_options_set_ondisk_path")
    self.swiftscan_cas_options_set_plugin_option = loadOptional("swiftscan_cas_options_set_plugin_option")
    self.swiftscan_cas_options_dispose = loadOptional("swiftscan_cas_options_dispose")
    self.swiftscan_cas_create_from_options = loadOptional("swiftscan_cas_create_from_options")
    self.swiftscan_cas_get_ondisk_size = loadOptional("swiftscan_cas_get_ondisk_size")
    self.swiftscan_cas_set_ondisk_size_limit = loadOptional("swiftscan_cas_set_ondisk_size_limit")
    self.swiftscan_cas_prune_ondisk_data = loadOptional("swiftscan_cas_prune_ondisk_data")
    self.swiftscan_cas_dispose = loadOptional("swiftscan_cas_dispose")
    self.swiftscan_cache_compute_key = loadOptional("swiftscan_cache_compute_key")
    self.swiftscan_cache_compute_key_from_input_index = loadOptional("swiftscan_cache_compute_key_from_input_index")
    self.swiftscan_cas_store = loadOptional("swiftscan_cas_store")

    self.swiftscan_cache_query = loadOptional("swiftscan_cache_query")
    self.swiftscan_cache_query_async = loadOptional("swiftscan_cache_query_async")

    self.swiftscan_cached_compilation_get_num_outputs = loadOptional("swiftscan_cached_compilation_get_num_outputs")
    self.swiftscan_cached_compilation_get_output = loadOptional("swiftscan_cached_compilation_get_output")
    self.swiftscan_cached_compilation_make_global_async = loadOptional("swiftscan_cached_compilation_make_global_async")
    self.swiftscan_cached_compilation_is_uncacheable = loadOptional("swiftscan_cached_compilation_is_uncacheable")
    self.swiftscan_cached_compilation_dispose = loadOptional("swiftscan_cached_compilation_dispose")

    self.swiftscan_cached_output_load = loadOptional("swiftscan_cached_output_load")
    self.swiftscan_cached_output_load_async = loadOptional("swiftscan_cached_output_load_async")
    self.swiftscan_cached_output_is_materialized = loadOptional("swiftscan_cached_output_is_materialized")
    self.swiftscan_cached_output_get_casid = loadOptional("swiftscan_cached_output_get_casid")
    self.swiftscan_cached_output_get_name = loadOptional("swiftscan_cached_output_get_name")
    self.swiftscan_cached_output_dispose = loadOptional("swiftscan_cached_output_dispose")

    self.swiftscan_cache_action_cancel = loadOptional("swiftscan_cache_action_cancel")
    self.swiftscan_cache_cancellation_token_dispose = loadOptional("swiftscan_cache_cancellation_token_dispose")

    self.swiftscan_cache_download_cas_object_async = loadOptional("swiftscan_cache_download_cas_object_async")

    self.swiftscan_cache_replay_instance_create = loadOptional("swiftscan_cache_replay_instance_create")
    self.swiftscan_cache_replay_instance_dispose = loadOptional("swiftscan_cache_replay_instance_dispose")
    self.swiftscan_cache_replay_compilation = loadOptional("swiftscan_cache_replay_compilation")

    self.swiftscan_cache_replay_result_get_stdout = loadOptional("swiftscan_cache_replay_result_get_stdout")
    self.swiftscan_cache_replay_result_get_stderr = loadOptional("swiftscan_cache_replay_result_get_stderr")
    self.swiftscan_cache_replay_result_dispose = loadOptional("swiftscan_cache_replay_result_dispose")

    self.swiftscan_diagnostic_get_source_location = loadOptional("swiftscan_diagnostic_get_source_location")
    self.swiftscan_source_location_get_buffer_identifier = loadOptional("swiftscan_source_location_get_buffer_identifier")
    self.swiftscan_source_location_get_line_number = loadOptional("swiftscan_source_location_get_line_number")
    self.swiftscan_source_location_get_column_number = loadOptional("swiftscan_source_location_get_column_number")

    self.swiftscan_module_info_get_link_libraries = loadOptional("swiftscan_module_info_get_link_libraries")
    self.swiftscan_link_library_info_get_link_name = loadOptional("swiftscan_link_library_info_get_link_name")
    self.swiftscan_link_library_info_get_is_framework = loadOptional("swiftscan_link_library_info_get_is_framework")
    self.swiftscan_link_library_info_get_should_force_load = loadOptional("swiftscan_link_library_info_get_should_force_load")

    // Swift Overlay Dependencies
    self.swiftscan_swift_textual_detail_get_swift_overlay_dependencies =
      loadOptional("swiftscan_swift_textual_detail_get_swift_overlay_dependencies")

    // Header dependencies of binary modules
    self.swiftscan_swift_binary_detail_get_header_dependencies =
      loadOptional("swiftscan_swift_binary_detail_get_header_dependencies")
    self.swiftscan_swift_binary_detail_get_header_dependency =
      loadOptional("swiftscan_swift_binary_detail_get_header_dependency")

    // Per-scan-query diagnostic output
    self.swiftscan_dependency_graph_get_diagnostics =
      loadOptional("swiftscan_dependency_graph_get_diagnostics")
    self.swiftscan_import_set_get_diagnostics =
      loadOptional("swiftscan_import_set_get_diagnostics")

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
    self.swiftscan_scan_invocation_get_argc =
      try loadRequired("swiftscan_scan_invocation_get_argc")
    self.swiftscan_scan_invocation_get_argv =
      try loadRequired("swiftscan_scan_invocation_get_argv")
    self.swiftscan_dependency_graph_dispose =
      try loadRequired("swiftscan_dependency_graph_dispose")
    self.swiftscan_import_set_dispose =
      try loadRequired("swiftscan_import_set_dispose")
    self.swiftscan_scan_invocation_dispose =
      try loadRequired("swiftscan_scan_invocation_dispose")
    self.swiftscan_dependency_graph_create =
      try loadRequired("swiftscan_dependency_graph_create")
    self.swiftscan_import_set_create =
      try loadRequired("swiftscan_import_set_create")
  }
}

// TODO: Move the following functions to TSC?
/// Helper function to scan a sequence type to help generate pointers for C String Arrays.
func scan<
  S: Sequence, U
>(_ seq: S, _ initial: U, _ combine: (U, S.Element) -> U) -> [U] {
  var result: [U] = []
  result.reserveCapacity(seq.underestimatedCount)
  var runningResult = initial
  for element in seq {
    runningResult = combine(runningResult, element)
    result.append(runningResult)
  }
  return result
}

/// Perform an  `action` passing it a `const char **` constructed out of `[String]`
@_spi(Testing) public func withArrayOfCStrings<T>(
  _ args: [String],
  _ body: (UnsafeMutablePointer<UnsafePointer<Int8>?>?) -> T
) -> T {
  let argsCounts = Array(args.map { $0.utf8.count + 1 })
  let argsOffsets = [0] + scan(argsCounts, 0, +)
  let argsBufferSize = argsOffsets.last!
  var argsBuffer: [UInt8] = []
  argsBuffer.reserveCapacity(argsBufferSize)
  for arg in args {
    argsBuffer.append(contentsOf: arg.utf8)
    argsBuffer.append(0)
  }
  return argsBuffer.withUnsafeMutableBufferPointer {
    (argsBuffer) in
    let ptr = UnsafeRawPointer(argsBuffer.baseAddress!).bindMemory(
      to: Int8.self, capacity: argsBuffer.count)
    var cStrings: [UnsafePointer<Int8>?] = argsOffsets.map { ptr + $0 }
    cStrings[cStrings.count - 1] = nil
    return cStrings.withUnsafeMutableBufferPointer {
      let unsafeString = UnsafeMutableRawPointer($0.baseAddress!).bindMemory(
        to: UnsafePointer<Int8>?.self, capacity: $0.count)
      return body(unsafeString)
    }
  }
}
