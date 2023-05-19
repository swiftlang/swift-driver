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

#define SWIFTSCAN_VERSION_MAJOR 0
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
typedef struct swiftscan_dependency_graph_s *swiftscan_dependency_graph_t;
typedef struct swiftscan_import_set_s *swiftscan_import_set_t;
typedef struct swiftscan_diagnostic_info_s *swiftscan_diagnostic_info_t;

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

//=== Batch Scan Input Specification --------------------------------------===//

typedef struct swiftscan_batch_scan_entry_s *swiftscan_batch_scan_entry_t;
typedef struct {
  swiftscan_batch_scan_entry_t *modules;
  size_t count;
} swiftscan_batch_scan_input_t;
typedef struct {
  swiftscan_dependency_graph_t *results;
  size_t count;
} swiftscan_batch_scan_result_t;

//=== Scanner Invocation Specification ------------------------------------===//

typedef struct swiftscan_scan_invocation_s *swiftscan_scan_invocation_t;
typedef void *swiftscan_scanner_t;

//=== libSwiftScan Functions ------------------------------------------------===//

typedef struct {

  //=== Dependency Result Functions -----------------------------------------===//
  swiftscan_string_ref_t
  (*swiftscan_dependency_graph_get_main_module_name)(swiftscan_dependency_graph_t);
  swiftscan_dependency_set_t *
  (*swiftscan_dependency_graph_get_dependencies)(swiftscan_dependency_graph_t);

  //=== Dependency Module Info Functions ------------------------------------===//
  swiftscan_string_ref_t
  (*swiftscan_module_info_get_module_name)(swiftscan_dependency_info_t);
  swiftscan_string_ref_t
  (*swiftscan_module_info_get_module_path)(swiftscan_dependency_info_t);
  swiftscan_string_set_t *
  (*swiftscan_module_info_get_source_files)(swiftscan_dependency_info_t);
  swiftscan_string_set_t *
  (*swiftscan_module_info_get_direct_dependencies)(swiftscan_dependency_info_t);
  swiftscan_module_details_t
  (*swiftscan_module_info_get_details)(swiftscan_dependency_info_t);
  
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
  (*swiftscan_swift_textual_detail_get_extra_pcm_args)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_textual_detail_get_context_hash)(swiftscan_module_details_t);
  bool
  (*swiftscan_swift_textual_detail_get_is_framework)(swiftscan_module_details_t);
  swiftscan_string_set_t *
  (*swiftscan_swift_textual_detail_get_swift_overlay_dependencies)(swiftscan_module_details_t);

  //=== Swift Binary Module Details query APIs ------------------------------===//
  swiftscan_string_ref_t
  (*swiftscan_swift_binary_detail_get_compiled_module_path)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_binary_detail_get_module_doc_path)(swiftscan_module_details_t);
  swiftscan_string_ref_t
  (*swiftscan_swift_binary_detail_get_module_source_info_path)(swiftscan_module_details_t);
  bool
  (*swiftscan_swift_binary_detail_get_is_framework)(swiftscan_module_details_t);

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
  swiftscan_string_set_t *
  (*swiftscan_clang_detail_get_captured_pcm_args)(swiftscan_module_details_t);

  //=== Batch Scan Input Functions ------------------------------------------===//
  swiftscan_batch_scan_input_t *
  (*swiftscan_batch_scan_input_create)(void);
  void
  (*swiftscan_batch_scan_input_set_modules)(swiftscan_batch_scan_input_t *, int, swiftscan_batch_scan_entry_t *);

  //=== Batch Scan Entry Functions ------------------------------------------===//
  swiftscan_batch_scan_entry_t
  (*swiftscan_batch_scan_entry_create)(void);
  void
  (*swiftscan_batch_scan_entry_set_module_name)(swiftscan_batch_scan_entry_t, const char *);
  void
  (*swiftscan_batch_scan_entry_set_arguments)(swiftscan_batch_scan_entry_t, const char *);
  void
  (*swiftscan_batch_scan_entry_set_is_swift)(swiftscan_batch_scan_entry_t, bool);
  swiftscan_string_ref_t
  (*swiftscan_batch_scan_entry_get_module_name)(swiftscan_batch_scan_entry_t);
  swiftscan_string_ref_t
  (*swiftscan_batch_scan_entry_get_arguments)(swiftscan_batch_scan_entry_t);
  bool
  (*swiftscan_batch_scan_entry_get_is_swift)(swiftscan_batch_scan_entry_t);

  //=== Prescan Result Functions --------------------------------------------===//
  swiftscan_string_set_t *
  (*swiftscan_import_set_get_imports)(swiftscan_import_set_t);

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
  void
  (*swiftscan_batch_scan_entry_dispose)(swiftscan_batch_scan_entry_t);
  void
  (*swiftscan_batch_scan_input_dispose)(swiftscan_batch_scan_input_t *);
  void
  (*swiftscan_batch_scan_result_dispose)(swiftscan_batch_scan_result_t *);
  void
  (*swiftscan_scan_invocation_dispose)(swiftscan_scan_invocation_t);

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
  swiftscan_batch_scan_result_t *
  (*swiftscan_batch_scan_result_create)(swiftscan_scanner_t,
                                        swiftscan_batch_scan_input_t *,
                                        swiftscan_scan_invocation_t);
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
  void
  (*swiftscan_diagnostics_set_dispose)(swiftscan_diagnostic_set_t*);

  //=== Scanner Cache Functions ---------------------------------------------===//
  void (*swiftscan_scanner_cache_serialize)(swiftscan_scanner_t scanner, const char * path);
  bool (*swiftscan_scanner_cache_load)(swiftscan_scanner_t scanner, const char * path);
  void (*swiftscan_scanner_cache_reset)(swiftscan_scanner_t scanner);

} swiftscan_functions_t;

#endif // SWIFT_C_DEPENDENCY_SCAN_H
