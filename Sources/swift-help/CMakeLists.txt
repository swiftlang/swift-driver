# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_executable(swift-help
  main.swift)
target_link_libraries(swift-help PUBLIC
  SwiftOptions
  ArgumentParser
  TSCBasic)

# This is a fairly egregious workaround for the fact that in versions < 3.17,
# executables do not get `-rpath` linker arguments for their linked library
# dependencies (direct and transitive)
if(CMAKE_VERSION VERSION_LESS 3.17)
  get_target_property(TSC_UTIL_LIB TSCUtility LOCATION)
  get_filename_component(TSC_LIB_DIR ${TSC_UTIL_LIB} DIRECTORY)
  
  get_target_property(ARGPARSE_LIB ArgumentParser LOCATION)
  get_filename_component(ARGPARSE_LIB_DIR ${ARGPARSE_LIB} DIRECTORY)
  
  target_link_options(swift-help PUBLIC "LINKER:-rpath,${CMAKE_LIBRARY_OUTPUT_DIRECTORY},-rpath,${TSC_LIB_DIR},-rpath,${ARGPARSE_LIB_DIR}")
endif()
