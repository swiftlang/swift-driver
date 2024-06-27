//===--------------- llbuild.swift - Swift LLBuild Interaction ------------===//
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

// FIXME: This is slightly modified from the SwiftPM version,
// consider moving this to llbuild.

import struct Foundation.Data
import class Foundation.JSONEncoder
import class Foundation.JSONDecoder

import protocol TSCBasic.FileSystem

// We either import the llbuildSwift shared library or the llbuild framework.
#if canImport(llbuildSwift)
@_implementationOnly import llbuildSwift
@_implementationOnly import llbuild
#else
@_implementationOnly import llbuild
#endif

/// An llbuild value.
protocol LLBuildValue: Codable {
}

/// An llbuild key.
protocol LLBuildKey: Codable {
  /// The value that this key computes.
  associatedtype BuildValue: LLBuildValue

  /// The rule that this key operates on.
  associatedtype BuildRule: LLBuildRule
}

protocol LLBuildEngineDelegate {
  func lookupRule(rule: String, key: Key) -> Rule
}

final class LLBuildEngine {

  enum Error: Swift.Error, CustomStringConvertible {
    case failed(errors: [String])

    var description: String {
      switch self {
      case .failed(let errors):
        return errors.joined(separator: "\n")
      }
    }
  }

  fileprivate final class Delegate: BuildEngineDelegate {
    let delegate: LLBuildEngineDelegate
    var errors: [String] = []

    init(_ delegate: LLBuildEngineDelegate) {
      self.delegate = delegate
    }

    func lookupRule(_ key: Key) -> Rule {
      let ruleKey = RuleKey(key)
      return delegate.lookupRule(
        rule: ruleKey.rule, key: Key(ruleKey.data))
    }

    func error(_ message: String) {
      errors.append(message)
    }
  }

  private let engine: BuildEngine
  private let delegate: Delegate

  init(delegate: LLBuildEngineDelegate) {
    self.delegate = Delegate(delegate)
    engine = BuildEngine(delegate: self.delegate)
  }

  deinit {
    engine.close()
  }

  func build<T: LLBuildKey>(key: T) throws -> T.BuildValue {
    // Clear out any errors from the previous build.
    delegate.errors.removeAll()

    let encodedKey = RuleKey(
      rule: T.BuildRule.ruleName, data: key.toKey().data).toKey()
    let value = engine.build(key: encodedKey)

    // Throw if the engine encountered any fatal error during the build.
    if !delegate.errors.isEmpty || value.data.isEmpty {
      throw Error.failed(errors: delegate.errors)
    }

    return try T.BuildValue(value)
  }

  func attachDB(path: String, schemaVersion: Int = 2) throws {
    try engine.attachDB(path: path, schemaVersion: schemaVersion)
  }

  func close() {
    engine.close()
  }
}

// FIXME: Rename to something else.
class LLTaskBuildEngine {

  let engine: TaskBuildEngine
  let fileSystem: TSCBasic.FileSystem

  init(_ engine: TaskBuildEngine, fileSystem: TSCBasic.FileSystem) {
    self.engine = engine
    self.fileSystem = fileSystem
  }

  func taskNeedsInput<T: LLBuildKey>(_ key: T, inputID: Int) {
    let encodedKey = RuleKey(
      rule: T.BuildRule.ruleName, data: key.toKey().data).toKey()
    engine.taskNeedsInput(encodedKey, inputID: inputID)
  }

  func taskIsComplete<T: LLBuildValue>(_ result: T) {
    engine.taskIsComplete(result.toValue(), forceChange: false)
  }
}

/// An individual build rule.
class LLBuildRule: Rule, Task {

  /// The name of the rule.
  ///
  /// This name will be available in the delegate's lookupRule(rule:key:).
  class var ruleName: String {
    fatalError("subclass responsibility")
  }

  let fileSystem: TSCBasic.FileSystem

  init(fileSystem: TSCBasic.FileSystem) {
    self.fileSystem = fileSystem
  }

  func createTask() -> Task {
    return self
  }

  func start(_ engine: TaskBuildEngine) {
    self.start(LLTaskBuildEngine(engine, fileSystem: fileSystem))
  }

  func provideValue(_ engine: TaskBuildEngine, inputID: Int, value: Value) {
    self.provideValue(LLTaskBuildEngine(engine, fileSystem: fileSystem), inputID: inputID, value: value)
  }

  func inputsAvailable(_ engine: TaskBuildEngine) {
    self.inputsAvailable(LLTaskBuildEngine(engine, fileSystem: fileSystem))
  }

  // MARK:-

  func isResultValid(_ priorValue: Value) -> Bool {
    return true
  }

  func start(_ engine: LLTaskBuildEngine) {
  }

  func provideValue(_ engine: LLTaskBuildEngine, inputID: Int, value: Value) {
  }

  func inputsAvailable(_ engine: LLTaskBuildEngine) {
  }

  // Not strictly needed, but permits overriding for debugging
  func updateStatus(_ status: RuleStatus) {
  }
}

// MARK:- Helpers

private struct RuleKey: Codable {

  let rule: String
  let data: [UInt8]

  init(rule: String, data: [UInt8]) {
    self.rule = rule
    self.data = data
  }

  init(_ key: Key) {
    self.init(key.data)
  }

  init(_ data: [UInt8]) {
    self = try! fromBytes(data)
  }

  func toKey() -> Key {
    return try! Key(toBytes(self))
  }
}

extension LLBuildKey {
  init(_ key: Key) {
    self.init(key.data)
  }

  init(_ data: [UInt8]) {
    do {
      self = try fromBytes(data)
    } catch {
      let stringValue: String
      if let str = String(bytes: data, encoding: .utf8) {
        stringValue = str
      } else {
        stringValue = String(describing: data)
      }
      fatalError("Please file a bug at https://bugs.swift.org with this info -- LLBuildKey: ###\(error)### ----- ###\(stringValue)###")
    }
  }

  func toKey() -> Key {
    return try! Key(toBytes(self))
  }
}

extension LLBuildValue {
  init(_ value: Value) throws {
    do {
      self = try fromBytes(value.data)
    } catch {
      let stringValue: String
      if let str = String(bytes: value.data, encoding: .utf8) {
        stringValue = str
      } else {
        stringValue = String(describing: value.data)
      }
      fatalError("Please file a bug at https://bugs.swift.org with this info -- LLBuildValue: ###\(error)### ----- ###\(stringValue)###")
    }
  }

  func toValue() -> Value {
    return try! Value(toBytes(self))
  }
}

private func fromBytes<T: Decodable>(_ bytes: [UInt8]) throws -> T {
  var bytes = bytes
  let data = Data(bytes: &bytes, count: bytes.count)
  return try JSONDecoder().decode(T.self, from: data)
}

private func toBytes<T: Encodable>(_ value: T) throws -> [UInt8] {
  let encoder = JSONEncoder()
  if #available(macOS 10.13, iOS 11.0, watchOS 4.0, tvOS 11.0, *) {
    encoder.outputFormatting = [.sortedKeys]
  }
  let encoded = try encoder.encode(value)
  return [UInt8](encoded)
}
