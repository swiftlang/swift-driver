//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#include "include/tooling_shim.h"

bool swift_getSingleFrontendInvocationFromDriverArgumentsV3(const char *, int, const char**, bool(int, const char**),
                                                      void(swiftdriver_tooling_diagnostic_kind, const char*), bool, bool);
bool getSingleFrontendInvocationFromDriverArgumentsTest(const char *driverPath,
                                                        int argListCount,
                                                        const char** argList,
                                                        bool action(int argc, const char** argv),
                                                        void diagnosticCallback(swiftdriver_tooling_diagnostic_kind diagnosticKind,
                                                                                const char* message),
                                                        bool forceNoOutputs) {
  return swift_getSingleFrontendInvocationFromDriverArgumentsV3(driverPath, argListCount, argList,
                                                                action, diagnosticCallback, false, forceNoOutputs);
}
