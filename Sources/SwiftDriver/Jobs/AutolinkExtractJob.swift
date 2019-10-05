import TSCBasic
import TSCUtility

extension Driver {
  mutating func autolinkExtractJob(inputs: [TypedVirtualPath]) throws -> Job? {
    // On ELF platforms there's no built in autolinking mechanism, so we
    // pull the info we need from the .o files directly and pass them as an
    // argument input file to the linker.
    // FIXME: Also handle Cygwin and MinGW
    guard inputs.count > 0 && targetTriple.objectFormat == .elf else {
      return nil
    }

    var commandLine = [Job.ArgTemplate]()
    let output = VirtualPath.temporary("\(moduleName).autolink")

    commandLine.append(contentsOf: inputs.map { .path($0.file) })
    commandLine.appendFlag(.o)
    commandLine.appendPath(output)

    return Job(
      kind: .autolinkExtract,
      tool: .absolute(try toolchain.getToolPath(.swiftAutolinkExtract)),
      commandLine: commandLine,
      inputs: inputs,
      outputs: [.init(file: output, type: .autolink)]
    )
  }
}
