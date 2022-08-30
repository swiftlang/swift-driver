# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(SwiftOptions
  DriverKind.swift
  Option.swift
  OptionTable.swift
  ParsedOptions.swift
  OptionParsing.swift
  Options.swift
  PrefixTrie.swift)

target_link_libraries(SwiftOptions PUBLIC
  TSCBasic)

set_property(GLOBAL APPEND PROPERTY SWIFTDRIVER_EXPORTS SwiftOptions)

# NOTE: workaround for CMake not setting up include flags yet
set_target_properties(SwiftOptions PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

install(TARGETS SwiftOptions
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
