//===------------------ JobTracker.swift ----------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension ModuleDependencyGraph {
  // TODO: Incremental, check the relationship between batching and incremental compilation
  // Must delay batching until *after* incremental decisions
  
  ///Since the rest of the driver trucks in jobs, the correspondence must be tracked
  @_spi(Testing) public struct JobTracker {
    /// Keyed by swiftdeps filename, so we can get back to Jobs.
    private var jobsBySwiftDeps: [String: Job] = [:]
    
    
    func getJob(_ swiftDeps: String) -> Job {
      guard let job = jobsBySwiftDeps[swiftDeps] else {fatalError("All jobs should be tracked.")}
      assert(job.swiftDepsPaths.contains(swiftDeps),
             "jobsBySwiftDeps should be inverse of getSwiftDeps.")
      return job
    }
    
    @_spi(Testing) public mutating func registerJob(_ job: Job) {
      // No need to create any nodes; that will happen when the swiftdeps file is
      // read. Just record the correspondence.
      job.swiftDepsPaths.forEach { jobsBySwiftDeps[$0] = job }
    }
    
    @_spi(Testing) public var allJobs: [Job] {
      Array(jobsBySwiftDeps.values)
    }
  }
}
