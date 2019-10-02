import TSCBasic

extension Driver {
  /// Compute the output file for an image output.
  private func outputFileForImage(inputs: [InputFile]) -> VirtualPath {
    // FIXME: The check for __bad__ here, is
    if inputs.count == 1 && moduleName == "__bad__" && inputs.first!.file != .standardInput {
      // FIXME: llvm::sys::path::stem(BaseInput);
    }

    let path: String
    switch linkerOutputType! {
    case .dynamicLibrary:
      // FIXME: Ask toolchain for the dynamic library prefix and suffix
      path = "lib" + moduleName + ".dylib"

    case .staticLibrary:
      // FIXME: Ask toolchain for the static library suffix
      path = "lib" + moduleName + ".a"

    case .executable:
      path = moduleName
    }

    return .relative(RelativePath(path))
  }

  /// Link the given inputs.
  mutating func linkJob(inputs: [InputFile]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = []

    // Set up for linking.
    let linkerTool: Tool
    switch linkerOutputType! {
    case .executable:
      linkerTool = .dynamicLinker
      break

    case .dynamicLibrary:
      commandLine.appendFlag("-shared")
      linkerTool = .dynamicLinker

    case .staticLibrary:
      // FIXME: handle this, somehow
      linkerTool = .staticLinker
      break
    }

    // Add inputs.
    let inputFiles = inputs.map { $0.file }
    commandLine.append(contentsOf: inputFiles.map { Job.ArgTemplate.path($0) })

    // Add the output
    let outputFile = outputFileForImage(inputs: inputs)
    commandLine.appendFlag("-o")
    commandLine.append(.path(outputFile))

    return Job(tool: .absolute(try toolchain.getToolPath(linkerTool)), commandLine: commandLine, inputs: inputFiles, outputs: [outputFile])
  }
}
