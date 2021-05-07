# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_executable(swift-driver
  main.swift)
target_link_libraries(swift-driver PUBLIC
  SwiftDriver
  SwiftDriverExecution)

# This is a fairly egregious workaround for the fact that in versions < 3.17,
# executables do not get `-rpath` linker arguments for their linked library
# dependencies (direct and transitive)
if(CMAKE_VERSION VERSION_LESS 3.17)
  get_target_property(TSC_UTIL_LIB TSCUtility LOCATION)
  get_filename_component(TSC_LIB_DIR ${TSC_UTIL_LIB} DIRECTORY)

  get_target_property(LLBUILD_LIB llbuildSwift LOCATION)
  get_filename_component(LLBUILD_LIB_DIR ${LLBUILD_LIB} DIRECTORY)

  get_target_property(ARGPARSE_LIB ArgumentParser LOCATION)
  get_filename_component(ARGPARSE_LIB_DIR ${ARGPARSE_LIB} DIRECTORY)

  set_property(TARGET swift-driver PROPERTY BUILD_RPATH
    ${CMAKE_LIBRARY_OUTPUT_DIRECTORY};${TSC_LIB_DIR};${LLBUILD_LIB_DIR};${ARGPARSE_LIB_DIR})
endif()
