//===------ ExplicitModuleDependencyBuildInputs.swift - Test Inputs -------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import TSCBasic

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
              "isFramework": false
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
                "-fmodule-name=c_simd",
                "-o",
                "<replace-me>"
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
                "-explicit-interface-module-build",
                "-disable-implicit-swift-modules",
                "-Xcc",
                "-fno-implicit-modules",
                "-Xcc",
                "-fno-implicit-module-maps",
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
                "-Xcc",
                "-fmodule-file=SwiftShims=SwiftShims.pcm",
                "-Xcc",
                "-fmodule-map-file=/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/module.modulemap",
                "-enforce-exclusivity=unchecked",
                "-module-name",
                "Swift"
              ],
              "isFramework": false
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
                "-explicit-interface-module-build",
                "-disable-implicit-swift-modules",
                "-Xcc",
                "-fno-implicit-modules",
                "-Xcc",
                "-fno-implicit-module-maps",
                "-candidate-module-file",
                "\(AbsolutePath("/dummy/path2/SwiftOnoneSupport.swiftmodule").nativePathString(escaped: true))",
                "-candidate-module-file",
                "\(AbsolutePath("/dummy/path1/SwiftOnoneSupport.swiftmodule").nativePathString(escaped: true))",
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
                "-swift-module-file=Swift=Swift.swiftmodule",
                "-Xcc",
                "-fmodule-file=SwiftShims=SwiftShims.pcm",
                "-Xcc",
                "-fmodule-map-file=/Volumes/Compiler/build/Ninja-RelWithDebInfoAssert/swift-macosx-x86_64/lib/swift/shims/module.modulemap",
                "-module-name",
                "SwiftOnoneSupport"
              ],
              "isFramework": true
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

  static var fastDependencyScannerPlaceholderOutput: String {
    """
    {
      "mainModuleName": "A",
      "modules": [
        {
          "swift": "A"
        },
        {
          "modulePath": "A.swiftmodule",
          "sourceFiles": [
            "main.swift",
            "A.swift"
          ],
          "directDependencies": [
            {
              "swiftPlaceholder": "B"
            },
            {
              "swiftPlaceholder": "Swift"
            },
            {
              "swiftPlaceholder": "SwiftOnoneSupport"
            }
          ],
          "details": {
            "swift": {
              "isFramework": false
            }
          }
        },
        {
          "swiftPlaceholder": "B"
        },
        {
          "modulePath": "/Volumes/Data/Current/Driver/ExplicitPMTest/.build/x86_64-apple-macosx/debug/B.swiftmodule",
          "sourceFiles": [
          ],
          "directDependencies" : [
          ],
          "details": {
            "swiftPlaceholder": {
            }
          }
        },
        {
          "swiftPlaceholder": "Swift"
        },
        {
          "modulePath": "Swift.swiftmodule",
          "sourceFiles": [
          ],
          "directDependencies": [
          ],
          "details": {
            "swiftPlaceholder": {
            }
          }
        },
        {
          "swiftPlaceholder": "SwiftOnoneSupport"
        },
        {
          "modulePath": "SwiftOnoneSupport.swiftmodule",
          "sourceFiles": [
          ],
          "directDependencies": [
          ],
          "details": {
            "swiftPlaceholder": {
            }
          }
        }
      ]
    }
    """
  }

  static var mergeGraphInput1: String {
    """
    {
      "mainModuleName": "A",
      "modules": [
        {
          "swift": "A"
        },
        {
          "modulePath": "A.swiftmodule",
          "sourceFiles": [
            "/A/A.swift"
          ],
          "directDependencies": [
            {
              "clang": "B"
            }
          ],
          "details": {
            "swift": {
              "isFramework": false
            }
          }
        },
        {
          "clang": "B"
        },
        {
          "modulePath": "B.pcm",
          "sourceFiles": [
            "/B/module.map",
            "/B/include/b.h"
          ],
          "directDependencies": [
               {
                 "clang": "D"
               }
          ],
          "details": {
            "clang": {
              "moduleMapPath": "/B/module.map",
              "contextHash": "2QEMRLNY63H2N",
              "commandLine": [
                "-remove-preceeding-explicit-module-build-incompatible-options",
                "-fno-implicit-modules",
                "-emit-module",
                "-fmodule-name=c_simd"
              ]
            }
          }
        }
      ]
    }
    """
  }

  static var simpleDependencyGraphInput: String {
    """
    {
      "mainModuleName": "simpleTestModule",
      "modules": [
        {
          "swift": "simpleTestModule"
        },
        {
          "modulePath": "simpleTestModule.swiftmodule",
          "sourceFiles": [
            "/main/simpleTestModule.swift"
          ],
          "directDependencies": [
            {
              "swift": "B"
            },
          ],
          "details": {
            "swift": {
              "isFramework": false
            }
          }
        },
        {
          "swift" : "B"
        },
        {
          "modulePath" : "B.swiftmodule",
          "sourceFiles": [
          ],
          "directDependencies" : [
            {
              "swift": "A"
            },
          ],
          "details" : {
            "swift" : {
              "moduleInterfacePath": "B.swiftmodule/B.swiftinterface",
              "isFramework": false
            }
          }
        },
        {
          "swiftPrebuiltExternal" : "K"
        },
        {
          "modulePath" : "/tmp/K.swiftmodule",
          "directDependencies" : [
            {
              "swift": "A"
            },
          ],
          "details" : {
            "swiftPrebuiltExternal": {
              "compiledModulePath": "/tmp/K.swiftmodule",
              "isFramework": false
            }
          }
        },
        {
          "swift": "A"
        },
        {
          "modulePath": "/tmp/A.swiftmodule",
          "sourceFiles": [
            "/A/A.swift"
          ],
          "directDependencies" : [
          ],
          "details": {
            "swift": {
              "isFramework": false
            }
          }
        }
      ]
    }
    """
  }

  static var simpleDependencyGraphInputWithSwiftOverlayDep: String {
    """
    {
      "mainModuleName": "simpleTestModule",
      "modules": [
        {
          "swift": "A"
        },
        {
          "modulePath": "A.swiftmodule",
          "sourceFiles": [
          ],
          "directDependencies": [
            {
              "clang": "B"
            }
          ],
          "details": {
            "swift": {
              "moduleInterfacePath": "A.swiftmodule/A.swiftinterface",
              "isFramework": false,
              "swiftOverlayDependencies": [
                {
                  "swift": "B"
                }
              ]
            }
          }
        },
        {
          "swift": "simpleTestModule"
        },
        {
          "modulePath": "simpleTestModule.swiftmodule",
          "sourceFiles": [
            "/main/simpleTestModule.swift"
          ],
          "directDependencies": [
            {
              "swift": "A"
            },
          ],
          "details": {
            "swift": {
              "isFramework": false
            }
          }
        },
        {
          "swift" : "B"
        },
        {
          "modulePath" : "B.swiftmodule",
          "sourceFiles": [
          ],
          "directDependencies" : [
    
          ],
          "details" : {
            "swift" : {
              "moduleInterfacePath": "B.swiftmodule/B.swiftinterface",
              "isFramework": false
            }
          }
        },
        {
          "clang": "B"
        },
        {
          "modulePath": "B.pcm",
          "sourceFiles": [
            "/B/module.map",
            "/B/include/b.h"
          ],
          "directDependencies": [
          ],
          "details": {
            "clang": {
              "moduleMapPath": "/B/module.map",
              "contextHash": "2QEMRLNY63H2N",
              "commandLine": [
                "-remove-preceeding-explicit-module-build-incompatible-options",
                "-fno-implicit-modules",
                "-emit-module",
                "-fmodule-name=c_simd"
              ]
            }
          }
        }
      ]
    }
    """
  }

  static var mergeGraphInput2: String {
    """
    {
      "mainModuleName": "A",
      "modules": [
        {
          "swift": "A"
        },
        {
          "modulePath": "A.swiftmodule",
          "sourceFiles": [
            "/A/A.swift"
          ],
          "directDependencies": [
            {
              "clang": "B"
            },
          ],
          "details": {
            "swift": {
              "isFramework": false
            }
          }
        },
        {
          "clang": "B"
        },
        {
          "modulePath": "B.pcm",
          "sourceFiles": [
            "/B/module.map",
            "/B/include/b.h"
          ],
          "directDependencies": [
               {
                 "clang": "C"
               }
          ],
          "details": {
            "clang": {
              "moduleMapPath": "/B/module.map",
              "contextHash": "2QEMRLNY63H2N",
              "commandLine": [
                "-remove-preceeding-explicit-module-build-incompatible-options",
                "-fno-implicit-modules",
                "-emit-module",
                "-fmodule-name=c_simd"
              ]
            }
          }
        }
      ]
    }
    """
  }

  static var bPlaceHolderInput: String {
    """
    {
      "mainModuleName": "B",
      "modules": [
        {
          "swift": "B"
        },
        {
          "modulePath": "B.swiftmodule",
          "sourceFiles": [
            "/B/B.swift"
          ],
          "directDependencies": [
            {
              "swift": "Swift"
            },
            {
              "swift": "SwiftOnoneSupport"
            }
          ],
          "details": {
            "swift": {
              "isFramework": false
            }
          }
        },
        {
          "swift" : "Swift"
        },
        {
          "modulePath" : "Swift.swiftmodule",
          "sourceFiles": [
          ],
          "directDependencies" : [
          ],
          "details" : {
            "swift" : {
              "moduleInterfacePath": "Swift.swiftmodule/x86_64-apple-macos.swiftinterface",
              "isFramework": false,
              "explicitCompiledModulePath" : "M/Swift.swiftmodule"
            }
          }
        },
        {
          "swift" : "SwiftOnoneSupport"
        },
        {
          "modulePath" : "SwiftOnoneSupport.swiftmodule",
          "sourceFiles": [
          ],
          "directDependencies" : [
            {
              "swift" : "Swift"
            }
          ],
          "details" : {
            "swift" : {
              "moduleInterfacePath": "SwiftOnoneSupport.swiftmodule/x86_64-apple-macos.swiftinterface",
              "isFramework": false,
              "explicitCompiledModulePath" : "S/SwiftOnoneSupport.swiftmodule"
            }
          }
        }
      ]
    }
    """
  }
}

