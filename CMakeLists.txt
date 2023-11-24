# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

if(POLICY CMP0091)
  cmake_policy(SET CMP0091 NEW)
endif()

cmake_minimum_required(VERSION 3.19.6)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules)

project(SwiftDriver LANGUAGES C Swift)

set(CMAKE_Swift_LANGUAGE_VERSION 5)
set(CMAKE_Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/swift)
set(CMAKE_Swift_COMPILE_OPTIONS_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

set(CMAKE_MACOSX_RPATH YES)
set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)

# ensure Swift compiler can find _CSwiftScan
add_compile_options($<$<COMPILE_LANGUAGE:Swift>:-I$<SEMICOLON>${CMAKE_CURRENT_SOURCE_DIR}/Sources/CSwiftScan/include>)

option(BUILD_SHARED_LIBS "Build shared libraries by default" YES)

find_package(TSC CONFIG REQUIRED)

find_package(LLBuild CONFIG)
if(NOT LLBuild_FOUND)
  find_package(LLBuild REQUIRED)
endif()

find_package(dispatch QUIET)
find_package(Foundation QUIET)
find_package(Yams CONFIG REQUIRED)
find_package(ArgumentParser CONFIG REQUIRED)

add_subdirectory(Sources)
add_subdirectory(cmake/modules)
