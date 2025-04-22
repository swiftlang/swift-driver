# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(SwiftDriver
  "ExplicitModuleBuilds/ExplicitDependencyBuildPlanner.swift"
  "ExplicitModuleBuilds/ModuleDependencyScanning.swift"
  "ExplicitModuleBuilds/SerializableModuleArtifacts.swift"
  "ExplicitModuleBuilds/InterModuleDependencies/CommonDependencyOperations.swift"
  "ExplicitModuleBuilds/InterModuleDependencies/InterModuleDependencyGraph.swift"
  "ExplicitModuleBuilds/InterModuleDependencies/InterModuleDependencyOracle.swift"

  SwiftScan/DependencyGraphBuilder.swift
  SwiftScan/Loader.swift
  SwiftScan/SwiftScan.swift
  SwiftScan/SwiftScanCAS.swift

  Driver/CompilerMode.swift
  Driver/DebugInfo.swift
  Driver/Driver.swift
  Driver/LinkKind.swift
  Driver/ModuleOutputInfo.swift
  Driver/OutputFileMap.swift
  Driver/ToolExecutionDelegate.swift
  Driver/DriverVersion.swift
  Driver/WindowsExtensions.swift

  Execution/ArgsResolver.swift
  Execution/DriverExecutor.swift
  Execution/ParsableOutput.swift
  Execution/ProcessProtocol.swift

  "IncrementalCompilation/Bitcode/Bitcode.swift"
  "IncrementalCompilation/Bitcode/BitcodeElement.swift"
  "IncrementalCompilation/Bitcode/Bits.swift"
  "IncrementalCompilation/Bitcode/Bitstream.swift"
  "IncrementalCompilation/Bitcode/BitstreamReader.swift"
  "IncrementalCompilation/Bitcode/BitstreamVisitor.swift"
  "IncrementalCompilation/Bitcode/BitstreamWriter.swift"
  "IncrementalCompilation/Bitcode/BlockInfo.swift"

  "IncrementalCompilation/BuildRecord.swift"
  "IncrementalCompilation/BuildRecordInfo.swift"
  "IncrementalCompilation/DependencyGraphDotFileWriter.swift"
  "IncrementalCompilation/DependencyKey.swift"
  "IncrementalCompilation/DirectAndTransitiveCollections.swift"
  "IncrementalCompilation/ExternalDependencyAndFingerprintEnforcer.swift"
  "IncrementalCompilation/FirstWaveComputer.swift"
  "IncrementalCompilation/IncrementalCompilationSynchronizer.swift"
  "IncrementalCompilation/IncrementalCompilationState.swift"
  "IncrementalCompilation/IncrementalCompilationState+Extensions.swift"
  "IncrementalCompilation/IncrementalCompilationProtectedState.swift"
  "IncrementalCompilation/IncrementalDependencyAndInputSetup.swift"
  "IncrementalCompilation/InputInfo.swift"
  "IncrementalCompilation/KeyAndFingerprintHolder.swift"
  "IncrementalCompilation/ModuleDependencyGraph.swift"
  "IncrementalCompilation/ModuleDependencyGraphParts/DependencySource.swift"
  "IncrementalCompilation/ModuleDependencyGraphParts/Integrator.swift"
  "IncrementalCompilation/ModuleDependencyGraphParts/InternedStrings.swift"
  "IncrementalCompilation/ModuleDependencyGraphParts/Node.swift"
  "IncrementalCompilation/ModuleDependencyGraphParts/NodeFinder.swift"
  "IncrementalCompilation/ModuleDependencyGraphParts/Tracer.swift"
  "IncrementalCompilation/Multidictionary.swift"
  "IncrementalCompilation/SwiftSourceFile.swift"
  "IncrementalCompilation/SourceFileDependencyGraph.swift"
  "IncrementalCompilation/TwoDMap.swift"
  "IncrementalCompilation/TwoLevelMap.swift"

  Jobs/APIDigesterJobs.swift
  Jobs/AutolinkExtractJob.swift
  Jobs/CommandLineArguments.swift
  Jobs/CompileJob.swift
  Jobs/DarwinToolchain+LinkerSupport.swift
  Jobs/EmitModuleJob.swift
  Jobs/EmitSupportedFeaturesJob.swift
  Jobs/FrontendJobHelpers.swift
  Jobs/GenerateDSYMJob.swift
  Jobs/GeneratePCHJob.swift
  Jobs/GeneratePCMJob.swift
  Jobs/GenericUnixToolchain+LinkerSupport.swift
  Jobs/InterpretJob.swift
  Jobs/Job.swift
  Jobs/LinkJob.swift
  Jobs/MergeModuleJob.swift
  Jobs/ModuleWrapJob.swift
  Jobs/Planning.swift
  Jobs/PrintSupportedFeaturesJob.swift
  Jobs/PrintTargetInfoJob.swift
  Jobs/ReplJob.swift
  Jobs/SwiftHelpIntroJob.swift
  Jobs/Toolchain+InterpreterSupport.swift
  Jobs/Toolchain+LinkerSupport.swift
  Jobs/VerifyDebugInfoJob.swift
  Jobs/VerifyModuleInterfaceJob.swift
  Jobs/WebAssemblyToolchain+LinkerSupport.swift
  Jobs/WindowsToolchain+LinkerSupport.swift
  Jobs/PrebuiltModulesJob.swift

  Toolchains/DarwinToolchain.swift
  Toolchains/GenericUnixToolchain.swift
  Toolchains/Toolchain.swift
  Toolchains/WebAssemblyToolchain.swift
  Toolchains/WindowsToolchain.swift

  ToolingInterface/SimpleExecutor.swift
  ToolingInterface/ToolingUtil.swift

  Utilities/DOTJobGraphSerializer.swift
  Utilities/DOTModuleDependencyGraphSerializer.swift
  Utilities/DateAdditions.swift
  Utilities/Diagnostics.swift
  Utilities/FileList.swift
  Utilities/FileType.swift
  Utilities/PredictableRandomNumberGenerator.swift
  Utilities/RelativePathAdditions.swift
  Utilities/Sanitizer.swift
  Utilities/StringAdditions.swift
  Utilities/System.swift
  Utilities/Triple+Platforms.swift
  Utilities/Triple.swift
  Utilities/TypedVirtualPath.swift
  Utilities/Version.swift
  Utilities/VirtualPath.swift)

target_link_libraries(SwiftDriver PUBLIC
  TSCBasic
  TSCUtility
  SwiftOptions)
target_link_libraries(SwiftDriver PRIVATE
  CSwiftScan)

set_property(GLOBAL APPEND PROPERTY SWIFTDRIVER_EXPORTS SwiftDriver)

# NOTE: workaround for CMake not setting up include flags yet
set_target_properties(SwiftDriver PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS SwiftDriver
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
