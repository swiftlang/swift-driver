//===--- ExplicitModuleDependencyBuildInputs.swift - Test Inputs ----------===//
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

import Foundation

enum ModuleDependenciesInputs {
  static var fastDependencyScannerOutput: String {
    """
    {
      "mainModuleName": "test",
      "modules": [
        {
          "swift": "test"
        },
        {
          "modulePath": "test.swiftmodule",
          "sourceFiles": [
            "test.swift"
          ],
          "directDependencies": [
            {
              "clang": "c_simd"
            },
            {
              "swift": "Swift"
            },
            {
              "swift": "SwiftOnoneSupport"
            }
          ],
          "details": {
            "swift": {
              "extraPcmArgs": [
                "-Xcc",
                "-target",
                "-Xcc",
                "x86_64-apple-macosx10.15"
              ]
            }
          }
        },
        {
          "clang": "c_simd"
        },
        {
          "modulePath": "c_simd.pcm",
          "sourceFiles": [
            "/Volumes/clang-importer-sdk/usr/include/module.map",
            "/Volumes/clang-importer-sdk/usr/include/simd.h"
          ],
          "directDependencies": [
          ],
          "details": {
            "clang": {
              "moduleMapPath": "/Volumes/clang-importer-sdk/usr/include/module.map",
              "contextHash": "2QEMRLNY63H2N",
              "commandLine": [
                "-remove-preceeding-explicit-module-build-incompatible-options",
                "-fno-implicit-modules",
                "-emit-module",
                "-fmodule-name=c_simd"
              ]
            }
          }
        },
        {
          "swift": "Swift"
        },
        {
          "modulePath": "Swift.swiftmodule",
          "sourceFiles": [
          ],
          "directDependencies": [
            {
              "clang": "SwiftShims"
            }
          ],
          "details": {
            "swift": {
              "moduleInterfacePath": "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/macosx/Swift.swiftmodule/x86_64-apple-macos.swiftinterface",
              "contextHash": "2WMED1WFU2S4M",
              "commandLine": [
                "-compile-module-from-interface",
                "-target",
                "x86_64-apple-macosx10.15",
                "-sdk",
                "/Volumes/clang-importer-sdk",
                "-resource-dir",
                "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift",
                "-suppress-warnings",
                "-disable-objc-attr-requires-foundation-module",
                "-module-cache-path",
                "/var/folders/7b/chq5yqgn7fz8zhmw8tkz53d80000gn/C/org.llvm.clang.ac/ModuleCache",
                "-prebuilt-module-cache-path",
                "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/macosx/prebuilt-modules",
                "-track-system-dependencies",
                "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/macosx/Swift.swiftmodule/x86_64-apple-macos.swiftinterface",
                "-module-name",
                "Swift",
                "-o",
                "/var/folders/7b/chq5yqgn7fz8zhmw8tkz53d80000gn/C/org.llvm.clang.ac/ModuleCache/Swift-2WMED1WFU2S4M.swiftmodule",
                "-disable-objc-attr-requires-foundation-module",
                "-target",
                "x86_64-apple-macosx10.9",
                "-enable-objc-interop",
                "-enable-library-evolution",
                "-module-link-name",
                "swiftCore",
                "-parse-stdlib",
                "-swift-version",
                "5",
                "-O",
                "-enforce-exclusivity=unchecked",
                "-module-name",
                "Swift"
              ],
              "extraPcmArgs": [
                "-Xcc",
                "-target",
                "-Xcc",
                "x86_64-apple-macosx10.15"
              ]
            }
          }
        },
        {
          "swift": "SwiftOnoneSupport"
        },
        {
          "modulePath": "SwiftOnoneSupport.swiftmodule",
          "sourceFiles": [
          ],
          "directDependencies": [
            {
              "swift": "Swift"
            }
          ],
          "details": {
            "swift": {
              "moduleInterfacePath": "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/macosx/SwiftOnoneSupport.swiftmodule/x86_64-apple-macos.swiftinterface",
              "compiledModuleCandidates": [
                "/dummy/path1/SwiftOnoneSupport.swiftmodule",
                "/dummy/path2/SwiftOnoneSupport.swiftmodule"
              ],
              "contextHash": "1PC0P8MX6CFZA",
              "commandLine": [
                "-compile-module-from-interface",
                "-target",
                "x86_64-apple-macosx10.15",
                "-sdk",
                "/Volumes/clang-importer-sdk",
                "-resource-dir",
                "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift",
                "-suppress-warnings",
                "-disable-objc-attr-requires-foundation-module",
                "-module-cache-path",
                "/var/folders/7b/chq5yqgn7fz8zhmw8tkz53d80000gn/C/org.llvm.clang.ac/ModuleCache",
                "-prebuilt-module-cache-path",
                "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/macosx/prebuilt-modules",
                "-track-system-dependencies",
                "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/macosx/SwiftOnoneSupport.swiftmodule/x86_64-apple-macos.swiftinterface",
                "-module-name",
                "SwiftOnoneSupport",
                "-o",
                "/var/folders/7b/chq5yqgn7fz8zhmw8tkz53d80000gn/C/org.llvm.clang.ac/ModuleCache/SwiftOnoneSupport-1PC0P8MX6CFZA.swiftmodule",
                "-disable-objc-attr-requires-foundation-module",
                "-target",
                "x86_64-apple-macosx10.9",
                "-enable-objc-interop",
                "-enable-library-evolution",
                "-module-link-name",
                "swiftSwiftOnoneSupport",
                "-parse-stdlib",
                "-swift-version",
                "5",
                "-O",
                "-enforce-exclusivity=unchecked",
                "-module-name",
                "SwiftOnoneSupport"
              ],
              "extraPcmArgs": [
                "-Xcc",
                "-target",
                "-Xcc",
                "x86_64-apple-macosx10.15"
              ]
            }
          }
        },
        {
          "clang": "SwiftShims"
        },
        {
          "modulePath": "SwiftShims.pcm",
          "sourceFiles": [
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/Random.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/module.modulemap",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/SwiftStdint.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/CoreFoundationShims.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/SwiftStdbool.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/RefCount.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/SwiftStddef.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/Visibility.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/RuntimeShims.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/Target.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/System.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/UnicodeShims.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/AssertionReporting.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/HeapObject.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/KeyPath.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/RuntimeStubs.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/ThreadLocalStorage.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/FoundationShims.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/GlobalObjects.h",
            "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/LibcShims.h"
          ],
          "directDependencies": [
          ],
          "details": {
            "clang": {
              "moduleMapPath": "/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/module.modulemap",
              "contextHash": "2QEMRLNY63H2N",
              "commandLine": [
                "-remove-preceeding-explicit-module-build-incompatible-options",
                "-fno-implicit-modules",
                "-emit-module",
                "-fmodule-name=SwiftShims"
              ]
            }
          }
        }
      ]
    }
    """
  }
}
