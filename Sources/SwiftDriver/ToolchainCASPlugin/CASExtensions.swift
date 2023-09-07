//===------------------------ CASExtensions.swift -------------------------===//
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

extension llcas_data_t {
  init(data: UnsafeRawPointer?, size: Int) {
    self.init()
    self.data = data
    self.size = size
  }
}

extension llcas_functions_t {
  init(_ swiftscan: Loader.Handle) throws {
    self.init()
    // MARK: load APIs from the dylib.
    func load<T>(_ symbol: String) throws -> T {
      guard let sym: T = Loader.lookup(symbol: symbol, in: swiftscan) else {
        throw DependencyScanningError.missingRequiredSymbol(symbol)
      }
      return sym
    }
    self.llcas_get_plugin_version = try load("llcas_get_plugin_version")
    self.llcas_string_dispose = try load("llcas_string_dispose")
    self.llcas_cas_options_create = try load("llcas_cas_options_create")
    self.llcas_cas_options_dispose = try load("llcas_cas_options_dispose")
    self.llcas_cas_options_set_client_version = try load("llcas_cas_options_set_client_version")
    self.llcas_cas_options_set_ondisk_path = try load("llcas_cas_options_set_ondisk_path")
    self.llcas_cas_options_set_option = try load("llcas_cas_options_set_option")
    self.llcas_cas_create = try load("llcas_cas_create")
    self.llcas_cas_dispose = try load("llcas_cas_dispose")
    self.llcas_cas_get_hash_schema_name = try load("llcas_cas_get_hash_schema_name")
    self.llcas_digest_parse = try load("llcas_digest_parse")
    self.llcas_digest_print = try load("llcas_digest_print")
    self.llcas_cas_get_objectid = try load("llcas_cas_get_objectid")
    self.llcas_objectid_get_digest = try load("llcas_objectid_get_digest")
    self.llcas_cas_contains_object = try load("llcas_cas_contains_object")
    self.llcas_cas_load_object = try load("llcas_cas_load_object")
    self.llcas_cas_load_object_async = try load("llcas_cas_load_object_async")
    self.llcas_cas_store_object = try load("llcas_cas_store_object")
    self.llcas_loaded_object_get_data = try load("llcas_loaded_object_get_data")
    self.llcas_loaded_object_get_refs = try load("llcas_loaded_object_get_refs")
    self.llcas_object_refs_get_count = try load("llcas_object_refs_get_count")
    self.llcas_object_refs_get_id = try load("llcas_object_refs_get_id")
    self.llcas_actioncache_get_for_digest = try load("llcas_actioncache_get_for_digest")
    self.llcas_actioncache_get_for_digest_async = try load("llcas_actioncache_get_for_digest_async")
    self.llcas_actioncache_put_for_digest = try load("llcas_actioncache_put_for_digest")
    self.llcas_actioncache_put_for_digest_async = try load("llcas_actioncache_put_for_digest_async")
  }
}
