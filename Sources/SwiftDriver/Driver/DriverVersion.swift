//===------ DriverVersion.swift - Swift Driver Source Version--------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
extension Driver {
#if SWIFT_DRIVER_VERSION_DEFINED
  static let driverSourceVersion: String = SWIFT_DRIVER_VERSION
#else
  static let driverSourceVersion: String = ""
#endif
}
