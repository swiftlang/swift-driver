import TSCBasic
import TSCUtility

extension Driver {
  func generateDSYMJob(inputs: [TypedVirtualPath]) throws -> Job {
    assert(inputs.count == 1)
    let input = inputs[0]
    let outputPath = try input.file.replacingExtension(with: .dSYM)

    var commandLine = [Job.ArgTemplate]()
    commandLine.appendPath(input.file)

    commandLine.appendFlag(.o)
    commandLine.appendPath(outputPath)

    return Job(
      kind: .generateDSYM,
      tool: .absolute(try toolchain.getToolPath(.dsymutil)),
      commandLine: commandLine,
      displayInputs: [],
      inputs: inputs,
      outputs: [.init(file: outputPath, type: .dSYM)]
    )
  }
}
