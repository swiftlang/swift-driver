import TSCBasic

extension Driver {
  mutating func mergeModuleJob(inputs: [InputFile]) throws -> Job {
    var commandLine: [Job.ArgTemplate] = []
    commandLine.appendFlag("-version")

    return Job(
      tool: .absolute(try toolchain.getToolPath(.swiftCompiler)),
      commandLine: commandLine,
      inputs: inputs.map{ $0.file },
      outputs: [.temporary("fake-merge-module-output.txt")]
    )
  }
}
