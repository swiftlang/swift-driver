# This source file is part of the Swift open source project
#
# Copyright (c) 2020 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(SwiftDriverExecution
  llbuild.swift
  MultiJobExecutor.swift
  SwiftDriverExecutor.swift)

target_link_libraries(SwiftDriverExecution PUBLIC
  TSCBasic
  TSCUtility
  SwiftOptions
  SwiftDriver)
target_link_libraries(SwiftDriverExecution PRIVATE
  llbuild
  llbuildSwift)

set_property(GLOBAL APPEND PROPERTY SWIFTDRIVER_EXPORTS SwiftDriverExecution)

# NOTE: workaround for CMake not setting up include flags yet
set_target_properties(SwiftDriverExecution PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS SwiftDriverExecution
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
if(MSVC)
  install(FILES $<TARGET_FILE_DIR:SwiftDriverExecution>/$<TARGET_FILE_BASE_NAME:SwiftDriverExecution>.pdb
    DESTINATION bin
    OPTIONAL)
endif()
