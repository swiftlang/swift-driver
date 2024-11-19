# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_executable(swift-build-sdk-interfaces
  main.swift)
target_link_libraries(swift-build-sdk-interfaces PUBLIC
  SwiftDriver
  SwiftDriverExecution)

set_target_properties(swift-build-sdk-interfaces PROPERTIES
  INSTALL_RPATH "$<$<PLATFORM_ID:Darwin>:@executable_path/../lib/swift/macosx>")

install(TARGETS swift-build-sdk-interfaces
  DESTINATION bin)
