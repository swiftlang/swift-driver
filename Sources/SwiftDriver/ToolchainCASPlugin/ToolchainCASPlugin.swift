//===------------------------ ToolchainCASPlugin.swift --------------------===//
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

@_implementationOnly import CToolchainCASPlugin

import struct Foundation.Data
import protocol TSCBasic.DiagnosticData
import struct TSCBasic.AbsolutePath
import struct TSCBasic.Diagnostic

public enum CASError: Error, DiagnosticData {
  case failedToCreateOption
  case failedToCreate(String)
  case failedToStore(String)
  case cannotPrintDigest(String)

  public var description: String {
    switch self {
      case .failedToCreateOption:
        return "failed to create CAS options"
      case .failedToCreate(let reason):
        return "failed to create CAS: '\(reason)'"
      case .failedToStore(let reason):
        return "failed to store into CAS: '\(reason)'"
      case .cannotPrintDigest(let reason):
        return "cannot convert CAS digest into printable ID: '\(reason)'"
    }
  }
}

/// Wrapper for libToolchainCASPlugin.dylib, handling a CAS instance and its functions.
@_spi(Testing) public final class CASPlugin {
  /// The path to the libToolchainCASPlugin dylib.
  let path: AbsolutePath

  /// The handle to the dylib.
  let dylib: Loader.Handle

  /// libToolchainCASPlugin.dylib APIs.
  let api: llcas_functions_t;

  /// CASOptions.
  let options: llcas_cas_options_t

  /// CAS instance.
  let db: llcas_cas_t

  @_spi(Testing) public init(dylib path: AbsolutePath,
                             path ondisk: AbsolutePath?,
                             options args: [String: String]) throws {
    self.path = path
    #if os(Windows)
    self.dylib = try Loader.load(path.pathString, mode: [])
    #else
    self.dylib = try Loader.load(path.pathString, mode: [.lazy, .local, .first])
    #endif
    self.api = try llcas_functions_t(self.dylib)
    guard let opts = api.llcas_cas_options_create() else {
      throw CASError.failedToCreateOption
    }
    api.llcas_cas_options_set_client_version(opts, UInt32(LLCAS_VERSION_MAJOR), UInt32(LLCAS_VERSION_MINOR))
    if let onDiskPath = ondisk {
      api.llcas_cas_options_set_ondisk_path(opts, onDiskPath.pathString)
    }
    var c_err_msg: UnsafeMutablePointer<CChar>?
    for (name, value) in args {
      guard !api.llcas_cas_options_set_option(opts, name.cString(using: String.Encoding.utf8),
                                              value.cString(using:String.Encoding.utf8), &c_err_msg) else {
        let err_msg = String(cString: c_err_msg!)
        api.llcas_string_dispose(c_err_msg!)
        throw CASError.failedToCreate(err_msg)
      }
    }
    self.options = opts
    let c_cas = api.llcas_cas_create(options, &c_err_msg)
    guard let cas = c_cas else {
      let err_msg = String(cString: c_err_msg!)
      api.llcas_string_dispose(c_err_msg!)
      throw CASError.failedToCreate(err_msg)
    }
    self.db = cas
  }

  deinit {
    api.llcas_cas_options_dispose(options)
    api.llcas_cas_dispose(db)
    // Is it safe to close?
    dylib.leak()
  }

  // Store a data blob inside CAS and return the digest of CAS object.
  public func store(data: Data) throws -> String {
    var c_err_msg: UnsafeMutablePointer<CChar>?
    var cas_object_id = llcas_objectid_t()
    try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
      let cas_data = llcas_data_t(data: bytes.baseAddress, size: data.count)
      if api.llcas_cas_store_object(db, cas_data, nil, 0, &cas_object_id, &c_err_msg) {
        let msg = convertString(c_err_msg!)
        throw CASError.failedToStore(msg)
      }
    }
    return try getObjectIDString(id: cas_object_id)
  }
}

// Helper functions.
extension CASPlugin {
  private func convertString(_ c_err_msg: UnsafeMutablePointer<CChar>) -> String {
    let err_msg = String(cString: c_err_msg)
    api.llcas_string_dispose(c_err_msg)
    return err_msg
  }

  private func getObjectIDString(id: llcas_objectid_t) throws -> String {
    let cas_digest = api.llcas_objectid_get_digest(db, id)
    var cas_printed_id: UnsafeMutablePointer<CChar>?
    var c_err_msg: UnsafeMutablePointer<CChar>?
    if api.llcas_digest_print(db, cas_digest, &cas_printed_id, &c_err_msg) {
      let msg = convertString(c_err_msg!)
      throw CASError.cannotPrintDigest(msg)
    }
    return convertString(cas_printed_id!)
  }
}
