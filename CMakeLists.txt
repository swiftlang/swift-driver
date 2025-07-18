# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

cmake_minimum_required(VERSION 3.19.6)

if(POLICY CMP0077)
  cmake_policy(SET CMP0077 NEW)
endif()

if(POLICY CMP0091)
  cmake_policy(SET CMP0091 NEW)
endif()

project(SwiftDriver
  LANGUAGES C CXX Swift)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

set(CMAKE_MACOSX_RPATH YES)
set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake/modules)

set(CMAKE_Swift_COMPILE_OPTIONS_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
set(CMAKE_Swift_LANGUAGE_VERSION 5)
set(CMAKE_Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/swift)

# Generate build-ids
if(NOT CMAKE_SYSTEM_NAME STREQUAL "Darwin"
    AND NOT CMAKE_SYSTEM_NAME STREQUAL "Windows")
  add_link_options("LINKER:--build-id=sha1")
endif()

# ensure Swift compiler can find _CSwiftScan
add_compile_options($<$<COMPILE_LANGUAGE:Swift>:-I$<SEMICOLON>${CMAKE_CURRENT_SOURCE_DIR}/Sources/CSwiftScan/include>)

option(BUILD_SHARED_LIBS "Build shared libraries by default" YES)
option(SWIFT_DRIVER_BUILD_TOOLS "Build makeOption" NO)

# Toolchain Vended Dependencies
find_package(dispatch QUIET)
find_package(Foundation QUIET)

include(FetchContent)

set(VendoredDependencies)

find_package(ArgumentParser CONFIG)
if(NOT ArgumentParser_FOUND)
  message("-- Vending swift-argument-parser")
  FetchContent_Declare(ArgumentParser
    GIT_REPOSITORY https://github.com/apple/swift-argument-parser
    GIT_TAG 1.5.1)
  list(APPEND VendoredDependencies ArgumentParser)
endif()

find_package(LLBuild CONFIG)
if(NOT LLBuild_FOUND)
  if(APPLE)
    find_package(LLBuild REQUIRED)
  else()
    message("-- Vending swift-llbuild")
    set(LLBUILD_SUPPORT_BINDINGS Swift CACHE STRING "")
    FetchContent_Declare(LLBuild
      GIT_REPOSITORY https://github.com/apple/swift-llbuild
      GIT_TAG main)
    list(APPEND VendoredDependencies LLBuild)
  endif()
endif()

find_package(TSC CONFIG)
if(NOT TSC_FOUND)
  message("-- Vending swift-tools-support-core")
  FetchContent_Declare(ToolsSupportCore
    GIT_REPOSITORY https://github.com/apple/swift-tools-support-core
    GIT_TAG main)
  list(APPEND VendoredDependencies ToolsSupportCore)
endif()

set(_SD_SAVED_BUILD_TESTING ${BUILD_TESTING})
set(_SD_SAVED_BUILD_EXAMPLES ${BUILD_EXAMPLES})

set(BUILD_TESTING NO)
set(BUILD_EXAMPLES NO)

FetchContent_MakeAvailable(${VendoredDependencies})

set(BUILD_TESTING ${_SD_SAVED_BUILD_TESTING})
set(BUILD_EXAMPLES ${_SD_SAVED_BUILD_EXAMPLES})

add_subdirectory(Sources)
add_subdirectory(cmake/modules)
