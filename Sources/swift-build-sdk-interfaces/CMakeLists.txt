# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_executable(swift-build-sdk-interfaces
  main.swift)
target_link_libraries(swift-build-sdk-interfaces PUBLIC
  SwiftDriver
  SwiftDriverExecution)

install(TARGETS swift-build-sdk-interfaces
  DESTINATION bin)
if(MSVC)
  install(FILES $<TARGET_FILE_DIR:swift-build-sdk-interfaces>/$<TARGET_FILE_BASE_NAME:swift-build-sdk-interfaces>.pdb
    DESTINATION bin
    OPTIONAL)
endif()
