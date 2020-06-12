# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(SwiftDriver
  "Dependency Scanning/ModuleDependencyBuildGeneration.swift"
  "Dependency Scanning/InterModuleDependencyGraph.swift"

  Driver/CompilerMode.swift
  Driver/DebugInfo.swift
  Driver/Driver.swift
  Driver/LinkKind.swift
  Driver/ModuleOutputInfo.swift
  Driver/OutputFileMap.swift
  Driver/ToolExecutionDelegate.swift
  Driver/ModuleDependencyScanning.swift

  Execution/JobExecutor.swift
  Execution/ParsableOutput.swift
  Execution/ProcessProtocol.swift
  Execution/llbuild.swift

  "Incremental Compilation/IncrementalCompilation.swift"
  "Incremental Compilation/InputIInfoMap.swift"
  "Incremental Compilation/InputInfo.swift"
  "Incremental Compilation/SourceFileDependencyGraph.swift"

  Jobs/AutolinkExtractJob.swift
  Jobs/BackendJob.swift
  Jobs/CommandLineArguments.swift
  Jobs/CompileJob.swift
  Jobs/DarwinToolchain+LinkerSupport.swift
  Jobs/EmitModuleJob.swift
  Jobs/FrontendJobHelpers.swift
  Jobs/GenerateDSYMJob.swift
  Jobs/GeneratePCHJob.swift
  Jobs/GeneratePCMJob.swift
  Jobs/GenericUnixToolchain+LinkerSupport.swift
  Jobs/InterpretJob.swift
  Jobs/Job.swift
  Jobs/LinkJob.swift
  Jobs/MergeModuleJob.swift
  Jobs/Planning.swift
  Jobs/ReplJob.swift
  Jobs/Toolchain+InterpreterSupport.swift
  Jobs/Toolchain+LinkerSupport.swift
  Jobs/VerifyDebugInfoJob.swift

  Toolchains/DarwinToolchain.swift
  Toolchains/GenericUnixToolchain.swift
  Toolchains/Toolchain.swift

  Utilities/DOTJobGraphSerializer.swift
  Utilities/DateAdditions.swift
  Utilities/Diagnostics.swift
  Utilities/FileType.swift
  Utilities/PredictableRandomNumberGenerator.swift
  Utilities/RelativePathAdditions.swift
  Utilities/Sanitizer.swift
  Utilities/StringAdditions.swift
  Utilities/System.swift
  Utilities/Triple+Platforms.swift
  Utilities/Triple.swift
  Utilities/TypedVirtualPath.swift
  Utilities/VirtualPath.swift)

target_link_libraries(SwiftDriver PUBLIC
  TSCBasic
  SwiftOptions
  llbuildSwift
  CYaml
  Yams)

set_property(GLOBAL APPEND PROPERTY SWIFTDRIVER_EXPORTS SwiftDriver)

# NOTE: workaround for CMake not setting up include flags yet
set_target_properties(SwiftDriver PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

