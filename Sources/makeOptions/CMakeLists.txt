# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

find_package(LLVM CONFIG REQUIRED)
find_package(Clang CONFIG REQUIRED)
find_package(Swift CONFIG REQUIRED)

add_executable(makeOptions
  main.cpp
  makeOptions.cpp)
set_target_properties(makeOptions PROPERTIES
  CXX_STANDARD 17)
target_compile_definitions(makeOptions PRIVATE
  LLVM_DISABLE_ABI_BREAKING_CHECKS_ENFORCING=1
  LLVM_VERSION_MAJOR=${LLVM_VERSION_MAJOR})
target_include_directories(makeOptions PRIVATE
  ${SWIFT_INCLUDE_DIRS}
  ${LLVM_BUILD_BINARY_DIR}/include
  ${LLVM_BUILD_MAIN_INCLUDE_DIR})
