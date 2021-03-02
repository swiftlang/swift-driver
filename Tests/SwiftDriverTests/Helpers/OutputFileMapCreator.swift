//===--------------- OutputFileMapCreator.swift - Swift Testing -----------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import XCTest
import TSCBasic

import Foundation

struct OutputFileMapCreator {
  private let module: String
  private let inputPaths: [AbsolutePath]
  private let derivedData: AbsolutePath

  private init(module: String, inputPaths: [AbsolutePath], derivedData: AbsolutePath) {
    self.module = module
    self.inputPaths = inputPaths
    self.derivedData = derivedData
  }

  static func write(module: String,
               inputPaths: [AbsolutePath],
               derivedData: AbsolutePath,
               to dst: AbsolutePath) {
    let creator = Self(module: module, inputPaths: inputPaths, derivedData: derivedData)
    try! localFileSystem.writeFileContents(dst, bytes: ByteString(creator.generateData()))
  }

  private func generateDict() -> [String: [String: String]] {
    let master = ["swift-dependencies": "\(derivedData.pathString)/\(module)-master.swiftdeps"]
    func baseNameEntry(_ s: AbsolutePath) -> [String: String] {
      [
        "dependencies": ".d",
        "diagnostics": ".dia",
        "llvm-bc": ".bc",
        "object": ".o",
        "swift-dependencies": ".swiftdeps",
        "swiftmodule": "-partial.swiftmodule"
      ]
      .mapValues {"\(derivedData.appending(component: s.basenameWithoutExt))\($0)"}
    }
    return Dictionary(uniqueKeysWithValues:
                        inputPaths.map { ("\($0)", baseNameEntry($0)) }
    )
    .merging(["": master]) {_, _ in fatalError()}
  }

  private func generateData() -> Data {
    let d: [String: [String: String]] = generateDict()
    let enc = JSONEncoder()
    return try! enc.encode(d)
  }
}

