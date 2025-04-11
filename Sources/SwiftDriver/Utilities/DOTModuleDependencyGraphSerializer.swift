//===----------- DOTModuleDependencyGraphSerializer.swift - Swift ---------===//
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
import TSCBasic

/// Serializes a module dependency graph to a .dot graph
@_spi(Testing) public struct DOTModuleDependencyGraphSerializer {
  let graph: InterModuleDependencyGraph

  public init(_ interModuleDependencyGraph: InterModuleDependencyGraph) {
    self.graph = interModuleDependencyGraph
  }

  func label(for moduleId: ModuleDependencyId) -> String {
    let label: String
    switch moduleId {
    case .swift(let string):
      label = "\(string)"
    case .swiftPlaceholder(let string):
      label = "\(string) (Placeholder)"
    case .swiftPrebuiltExternal(let string):
      label = "\(string) (Prebuilt)"
    case .clang(let string):
      label = "\(string) (C)"
    }
    return label
  }

  func quoteName(_ name: String) -> String {
    return "\"" + name.replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }

  func outputNode(for moduleId: ModuleDependencyId) -> String {
    let nodeName = quoteName(label(for: moduleId))
    let output: String
    let font = "fontname=\"Helvetica Bold\""

    if moduleId == .swift(graph.mainModuleName) {
      output = "  \(nodeName) [shape=box, style=bold, color=navy, \(font)];\n"
    } else {
      switch moduleId {
      case .swift(_):
        output = "  \(nodeName) [style=bold, color=orange, style=filled, \(font)];\n"
      case .swiftPlaceholder(_):
        output = "  \(nodeName) [style=bold, color=gold, style=filled, \(font)];\n"
      case .swiftPrebuiltExternal(_):
        output = "  \(nodeName) [style=bold, color=darkorange3, style=filled, \(font)];\n"
      case .clang(_):
        output = "  \(nodeName) [style=bold, color=lightskyblue, style=filled, \(font)];\n"
      }
    }
    return output
  }

  public func writeDOT<Stream: TextOutputStream>(to stream: inout Stream) {
    stream.write("digraph Modules {\n")
    for (moduleId, moduleInfo) in graph.modules {
      stream.write(outputNode(for: moduleId))
      for dependencyId in moduleInfo.allDependencies {
        stream.write("  \(quoteName(label(for: moduleId))) -> \(quoteName(label(for: dependencyId))) [color=black];\n")
      }
    }
    stream.write("}\n")
  }
}
