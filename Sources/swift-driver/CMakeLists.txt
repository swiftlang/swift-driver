# This source file is part of the Swift open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_executable(swift-driver
  main.swift)
target_link_libraries(swift-driver PUBLIC
  SwiftDriver
  SwiftDriverExecution)

install(TARGETS swift-driver
  DESTINATION bin)
if(MSVC)
  install(FILES $<TARGET_FILE_DIR:swift-driver>/$<TARGET_FILE_BASE_NAME:swift-driver>.pdb
    DESTINATION bin
    OPTIONAL)
endif()
