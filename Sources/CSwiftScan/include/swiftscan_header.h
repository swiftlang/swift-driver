//===-- swiftscan_header.h - C API for Swift Dependency Scanning --*- C -*-===//
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

#ifndef SWIFT_C_DEPENDENCY_SCAN_H
#define SWIFT_C_DEPENDENCY_SCAN_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define SWIFTSCAN_VERSION_MAJOR 2
#define SWIFTSCAN_VERSION_MINOR 1

//=== Public Scanner Data Types -------------------------------------------===//

typedef struct {
  const void *data;
  size_t length;
} swiftscan_string_ref_t;

typedef struct {
  swiftscan_string_ref_t *strings;
  size_t count;
} swiftscan_string_set_t;

typedef enum {
  SWIFTSCAN_DEPENDENCY_INFO_SWIFT_TEXTUAL = 0,
  SWIFTSCAN_DEPENDENCY_INFO_SWIFT_BINARY = 1,
  SWIFTSCAN_DEPENDENCY_INFO_SWIFT_PLACEHOLDER = 2,
  SWIFTSCAN_DEPENDENCY_INFO_CLANG = 3
} swiftscan_dependency_info_kind_t;

typedef struct swiftscan_module_details_s *swiftscan_module_details_t;
typedef struct swiftscan_dependency_info_s *swiftscan_dependency_info_t;
typedef struct swiftscan_link_library_info_s *swiftscan_link_library_info_t;
typedef struct swiftscan_dependency_graph_s *swiftscan_dependency_graph_t;
typedef struct swiftscan_import_set_s *swiftscan_import_set_t;
typedef struct swiftscan_diagnostic_info_s *swiftscan_diagnostic_info_t;
typedef struct swiftscan_source_location_s *swiftscan_source_location_t;

typedef enum {
  SWIFTSCAN_DIAGNOSTIC_SEVERITY_ERROR = 0,
  SWIFTSCAN_DIAGNOSTIC_SEVERITY_WARNING = 1,
  SWIFTSCAN_DIAGNOSTIC_SEVERITY_NOTE = 2,
  SWIFTSCAN_DIAGNOSTIC_SEVERITY_REMARK = 3
} swiftscan_diagnostic_severity_t;
typedef struct {
  swiftscan_diagnostic_info_t *diagnostics;
  size_t count;
} swiftscan_diagnostic_set_t;
typedef struct {
  swiftscan_dependency_info_t *modules;
  size_t count;
} swiftscan_dependency_set_t;
typedef struct {
  swiftscan_link_library_info_t *link_libraries;
  size_t count;
} swiftscan_link_library_set_t;

//=== Scanner Invocation Specification ------------------------------------===//

typedef struct swiftscan_scan_invocation_s *swiftscan_scan_invocation_t;
typedef void *swiftscan_scanner_t;

//=== CAS/Caching Specification -------------------------------------------===//
typedef struct swiftscan_cas_options_s *swiftscan_cas_options_t;
typedef struct swiftscan_cas_s *swiftscan_cas_t;
typedef struct swiftscan_cached_compilation_s *swiftscan_cached_compilation_t;
typedef struct swiftscan_cached_output_s *swiftscan_cached_output_t;
typedef struct swiftscan_cache_replay_instance_s
    *swiftscan_cache_replay_instance_t;
typedef struct swiftscan_cache_replay_result_s *swiftscan_cache_replay_result_t;
typedef struct swiftscan_cache_cancellation_token_s
    *swiftscan_cache_cancellation_token_t;

//=== libSwiftScan Functions ------------------------------------------------===//

typedef struct {

  //=== Dependency Result Functions -----------------------------------------===//
  swiftscan_string_ref_t
  (*swiftscan_dependency_graph_get_main_module_name)(swiftscan_dependency_graph_t);
  swiftscan_dependency_set_t *
  (*swiftscan_dependency_graph_get_dependencies)(swiftscan_dependency_graph_t);
  swiftscan_diagnostic_set_t *
  (*swiftscan_dependency_graph_get_diagnostics)(swiftscan_dependency_graph_t);

  //=== Dependency Module Info Functions ------------------------------------===//
  swiftscan_string_ref_t
  (*swiftscan_module_info_get_module_name)(swiftscan_dependency_info_t);
  swiftscan_string_ref_t
  (*swiftscan_module_info_get_module_path)(swiftscan_dependency_info_t);
  swiftscan_string_set_t *
  (*swiftscan_module_info_get_source_files)(swiftscan_dependency_info_t);
  swiftscan_string_set_t *
  (*swiftscan_module_info_get_direct_dependencies)(swiftscan_dependency_info_t);
  swiftscan_link_library_set_t *
  (*swiftscan_module_info_get_link_libraries)(swiftscan_dependency_graph_t);
  swiftscan_module_details_t
  (*swiftscan_module_info_get_details)(swiftscan_dependency_info_t);

  //=== Link Library Info Functions ------------------------------------===//
  swiftscan_string_ref_t
  (*swiftscan_link_library_info_get_link_name)(swiftscan_link_library_info_t);
  bool
  (*swiftscan_link_library_info_get_is_framework)(swiftscan_link_library_info_t);
  bool
  (*swiftscan_link_library_info_get_should_force_load)(swiftscan_link_library_info_t);

  //=== Dependency Module Info Details Functions ----------------------------===//
  swiftscan_dependency_info_kind_t
  (*swiftscan_module_detail_get_kind)(swiftscan_module_details_t);

  //=== Swift Textual Module Details query APIs -----------------------------===//
  swiftscan_string_ref_t
  (*swiftscan_swift_textual_detail_get_module_interface_path)(swiftscan_module_details_t);
  swiftscan_string_set_t *
  (*swiftscan_swift_textual_detail_get_compiled_module_candidates)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_textual_detail_get_bridging_header_path)(swiftscan_module_details_t);
  swiftscan_string_set_t *
  (*swiftscan_swift_textual_detail_get_bridging_source_files)(swiftscan_module_details_t);
  swiftscan_string_set_t *
  (*swiftscan_swift_textual_detail_get_bridging_module_dependencies)(swiftscan_module_details_t);
  swiftscan_string_set_t *
  (*swiftscan_swift_textual_detail_get_command_line)(swiftscan_module_details_t);
  swiftscan_string_set_t *
  (*swiftscan_swift_textual_detail_get_bridging_pch_command_line)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_textual_detail_get_context_hash)(swiftscan_module_details_t);
  bool
  (*swiftscan_swift_textual_detail_get_is_framework)(swiftscan_module_details_t);
  swiftscan_string_set_t *
  (*swiftscan_swift_textual_detail_get_swift_overlay_dependencies)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_textual_detail_get_module_cache_key)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_textual_detail_get_user_module_version)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_textual_detail_get_chained_bridging_header_path)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_textual_detail_get_chained_bridging_header_content)(swiftscan_module_details_t);

  //=== Swift Binary Module Details query APIs ------------------------------===//
  swiftscan_string_ref_t
  (*swiftscan_swift_binary_detail_get_compiled_module_path)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_binary_detail_get_module_doc_path)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_binary_detail_get_module_source_info_path)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_binary_detail_get_header_dependency)(swiftscan_module_details_t);
  bool
  (*swiftscan_swift_binary_detail_get_is_framework)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_binary_detail_get_module_cache_key)(swiftscan_module_details_t);
  swiftscan_string_set_t *
  (*swiftscan_swift_binary_detail_get_header_dependency_module_dependencies)(swiftscan_module_details_t);

  //=== Swift Binary Module Details deprecated APIs--------------------------===//
  swiftscan_string_set_t *
  (*swiftscan_swift_binary_detail_get_header_dependencies)(swiftscan_module_details_t);

  //=== Swift Placeholder Module Details query APIs -------------------------===//
  swiftscan_string_ref_t
  (*swiftscan_swift_placeholder_detail_get_compiled_module_path)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_placeholder_detail_get_module_doc_path)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_placeholder_detail_get_module_source_info_path)(swiftscan_module_details_t);

  //=== Clang Module Details query APIs -------------------------------------===//
  swiftscan_string_ref_t
  (*swiftscan_clang_detail_get_module_map_path)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_clang_detail_get_context_hash)(swiftscan_module_details_t);
  swiftscan_string_set_t *
  (*swiftscan_clang_detail_get_command_line)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_clang_detail_get_module_cache_key)(swiftscan_module_details_t);

  //=== Prescan Result Functions --------------------------------------------===//
  swiftscan_string_set_t *
  (*swiftscan_import_set_get_imports)(swiftscan_import_set_t);
  swiftscan_diagnostic_set_t *
  (*swiftscan_import_set_get_diagnostics)(swiftscan_import_set_t);

  //=== Scanner Invocation Functions ----------------------------------------===//
  swiftscan_scan_invocation_t
  (*swiftscan_scan_invocation_create)();
  void
  (*swiftscan_scan_invocation_set_working_directory)(swiftscan_scan_invocation_t, const char *);
  void
  (*swiftscan_scan_invocation_set_argv)(swiftscan_scan_invocation_t, int, const char **);
  swiftscan_string_ref_t
  (*swiftscan_scan_invocation_get_working_directory)(swiftscan_scan_invocation_t);
  int
  (*swiftscan_scan_invocation_get_argc)(swiftscan_scan_invocation_t);
  swiftscan_string_set_t *
  (*swiftscan_scan_invocation_get_argv)(swiftscan_scan_invocation_t);

  //=== Cleanup Functions ---------------------------------------------------===//
  void
  (*swiftscan_string_dispose)(swiftscan_string_ref_t);
  void
  (*swiftscan_string_set_dispose)(swiftscan_string_set_t *);
  void
  (*swiftscan_dependency_graph_dispose)(swiftscan_dependency_graph_t);
  void
  (*swiftscan_import_set_dispose)(swiftscan_import_set_t);

  //=== Target Info Functions-------- ---------------------------------------===//
  swiftscan_string_ref_t
  (*swiftscan_compiler_target_info_query_v2)(swiftscan_scan_invocation_t,
                                             const char *);

  //=== Functionality Query Functions ---------------------------------------===//
  swiftscan_string_set_t *
  (*swiftscan_compiler_supported_arguments_query)(void);
  swiftscan_string_set_t *
  (*swiftscan_compiler_supported_features_query)(void);

  //=== Scanner Functions ---------------------------------------------------===//
  swiftscan_scanner_t (*swiftscan_scanner_create)(void);
  void (*swiftscan_scanner_dispose)(swiftscan_scanner_t);
  swiftscan_dependency_graph_t
  (*swiftscan_dependency_graph_create)(swiftscan_scanner_t, swiftscan_scan_invocation_t);
  swiftscan_import_set_t
  (*swiftscan_import_set_create)(swiftscan_scanner_t, swiftscan_scan_invocation_t);

  //=== Scanner Diagnostics -------------------------------------------------===//
  swiftscan_diagnostic_set_t*
  (*swiftscan_scanner_diagnostics_query)(swiftscan_scanner_t);
  void
  (*swiftscan_scanner_diagnostics_reset)(swiftscan_scanner_t);
  swiftscan_string_ref_t
  (*swiftscan_diagnostic_get_message)(swiftscan_diagnostic_info_t);
  swiftscan_diagnostic_severity_t
  (*swiftscan_diagnostic_get_severity)(swiftscan_diagnostic_info_t);
  swiftscan_source_location_t
  (*swiftscan_diagnostic_get_source_location)(swiftscan_diagnostic_info_t);
  void
  (*swiftscan_diagnostics_set_dispose)(swiftscan_diagnostic_set_t*);
  void
  (*swiftscan_scan_invocation_dispose)(swiftscan_scan_invocation_t);

  //=== Source Location -----------------------------------------------------===//
  swiftscan_string_ref_t
  (*swiftscan_source_location_get_buffer_identifier)(swiftscan_source_location_t);
  int64_t
  (*swiftscan_source_location_get_line_number)(swiftscan_source_location_t);
  int64_t
  (*swiftscan_source_location_get_column_number)(swiftscan_source_location_t);

  //=== Scanner CAS Operations ----------------------------------------------===//
  swiftscan_cas_options_t (*swiftscan_cas_options_create)(void);
  int64_t (*swiftscan_cas_get_ondisk_size)(swiftscan_cas_t,
                                           swiftscan_string_ref_t *error);
  bool (*swiftscan_cas_set_ondisk_size_limit)(swiftscan_cas_t,
                                              int64_t size_limit,
                                              swiftscan_string_ref_t *error);
  bool (*swiftscan_cas_prune_ondisk_data)(swiftscan_cas_t,
                                          swiftscan_string_ref_t *error);
  void (*swiftscan_cas_options_dispose)(swiftscan_cas_options_t options);
  void (*swiftscan_cas_options_set_ondisk_path)(swiftscan_cas_options_t options,
                                                const char *path);
  void (*swiftscan_cas_options_set_plugin_path)(swiftscan_cas_options_t options,
                                                const char *path);
  bool (*swiftscan_cas_options_set_plugin_option)(
      swiftscan_cas_options_t options, const char *name, const char *value,
      swiftscan_string_ref_t *error);
  swiftscan_cas_t (*swiftscan_cas_create_from_options)(
      swiftscan_cas_options_t options, swiftscan_string_ref_t *error);
  void (*swiftscan_cas_dispose)(swiftscan_cas_t cas);
  swiftscan_string_ref_t (*swiftscan_cas_store)(swiftscan_cas_t cas,
                                                uint8_t *data, unsigned size,
                                                swiftscan_string_ref_t *error);
  swiftscan_string_ref_t (*swiftscan_cache_compute_key)(
      swiftscan_cas_t cas, int argc, const char **argv, const char *input,
      swiftscan_string_ref_t *error);
  swiftscan_string_ref_t (*swiftscan_cache_compute_key_from_input_index)(
      swiftscan_cas_t cas, int argc, const char **argv, unsigned input_index,
      swiftscan_string_ref_t *error);

  //=== Scanner Caching Query/Replay Operations -----------------------------===//
  swiftscan_cached_compilation_t (*swiftscan_cache_query)(
      swiftscan_cas_t cas, const char *key, bool globally,
      swiftscan_string_ref_t *error);
  void (*swiftscan_cache_query_async)(
      swiftscan_cas_t cas, const char *key, bool globally, void *ctx,
      void (*callback)(void *ctx, swiftscan_cached_compilation_t,
                       swiftscan_string_ref_t error),
      swiftscan_cache_cancellation_token_t *);


  unsigned (*swiftscan_cached_compilation_get_num_outputs)(
      swiftscan_cached_compilation_t);
  swiftscan_cached_output_t (*swiftscan_cached_compilation_get_output)(
      swiftscan_cached_compilation_t, unsigned idx);
  bool (*swiftscan_cached_compilation_is_uncacheable)(
      swiftscan_cached_compilation_t);
  void (*swiftscan_cached_compilation_make_global_async)(
      swiftscan_cached_compilation_t, void *ctx,
      void (*callback)(void *ctx, swiftscan_string_ref_t error),
      swiftscan_cache_cancellation_token_t *);
  void (*swiftscan_cached_compilation_dispose)(swiftscan_cached_compilation_t);

  bool (*swiftscan_cached_output_load)(swiftscan_cached_output_t,
                                       swiftscan_string_ref_t *error);
  void (*swiftscan_cached_output_load_async)(
      swiftscan_cached_output_t, void *ctx,
      void (*callback)(void *ctx, bool success, swiftscan_string_ref_t error),
      swiftscan_cache_cancellation_token_t *);
  bool (*swiftscan_cached_output_is_materialized)(swiftscan_cached_output_t);
  swiftscan_string_ref_t (*swiftscan_cached_output_get_casid)(
      swiftscan_cached_output_t);
  swiftscan_string_ref_t (*swiftscan_cached_output_get_name)(
      swiftscan_cached_output_t);
  void (*swiftscan_cached_output_dispose)(swiftscan_cached_output_t);

  void (*swiftscan_cache_action_cancel)(swiftscan_cache_cancellation_token_t);
  void (*swiftscan_cache_cancellation_token_dispose)(
      swiftscan_cache_cancellation_token_t);

  void (*swiftscan_cache_download_cas_object_async)(
      swiftscan_cas_t, const char *id, void *ctx,
      void (*callback)(void *ctx, bool success, swiftscan_string_ref_t error),
      swiftscan_cache_cancellation_token_t *);

  swiftscan_cache_replay_instance_t (*swiftscan_cache_replay_instance_create)(
      int argc, const char **argv, swiftscan_string_ref_t *error);
  void (*swiftscan_cache_replay_instance_dispose)(
      swiftscan_cache_replay_instance_t);

  swiftscan_cache_replay_result_t (*swiftscan_cache_replay_compilation)(
      swiftscan_cache_replay_instance_t, swiftscan_cached_compilation_t,
      swiftscan_string_ref_t *error);

  swiftscan_string_ref_t (*swiftscan_cache_replay_result_get_stdout)(
      swiftscan_cache_replay_result_t);
  swiftscan_string_ref_t (*swiftscan_cache_replay_result_get_stderr)(
      swiftscan_cache_replay_result_t);
  void (*swiftscan_cache_replay_result_dispose)(
      swiftscan_cache_replay_result_t);

} swiftscan_functions_t;

#endif // SWIFT_C_DEPENDENCY_SCAN_H
