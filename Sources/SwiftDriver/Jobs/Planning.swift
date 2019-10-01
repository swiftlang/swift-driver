/// Planning for builds
extension Driver {
  /// Plan a standard compilation, which produces jobs for compiling separate
  /// primary files.
  private mutating func planStandardCompile() -> [Job] {
    var jobs = [Job]()

    for input in inputFiles {
      switch input.type {
      case .swift, .sil, .sib:
        let job = compileJob(primaryInputs: [input], outputType: compilerOutputType)
        jobs.append(job)

      default:
        fatalError("unhandled thus far")
      }
    }

    // FIXME: Lots of follow-up actions for linking, merging modules, etc.

    return jobs
  }

  /// Plan a build by producing a set of jobs to complete the build/
  public mutating func planBuild() -> [Job] {
    // Plan the build.
    switch compilerMode {
    case .immediate, .repl, .singleCompile:
      fatalError("Not yet supported")

    case .standardCompile:
      return planStandardCompile()
    }
  }
}
