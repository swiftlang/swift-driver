//=== tooling_shim.h - C API Shim for Swift Driver Tooling Testing *- C -*-===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#ifndef SWIFT_C_TOOLING_TEST_SHIM_H
#define SWIFT_C_TOOLING_TEST_SHIM_H

#if __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stdio.h>

typedef enum {
  SWIFTDRIVER_TOOLING_DIAGNOSTIC_ERROR = 0,
  SWIFTDRIVER_TOOLING_DIAGNOSTIC_WARNING = 1,
  SWIFTDRIVER_TOOLING_DIAGNOSTIC_REMARK = 2,
  SWIFTDRIVER_TOOLING_DIAGNOSTIC_NOTE = 3
} swiftdriver_tooling_diagnostic_kind;

// A shim that will call out to the Swift-written C API of swift_getSingleFrontendInvocationFromDriverArgumentsV2
bool getSingleFrontendInvocationFromDriverArgumentsTest(const char *, int, const char**, bool(int, const char**),
                                                        void(swiftdriver_tooling_diagnostic_kind, const char*), bool);

#if __cplusplus
} // extern "C"
#endif // __cplusplus

#endif // SWIFT_C_TOOLING_TEST_SHIM_H
