import TSCBasic
import TSCUtility
import Foundation

/// Holds the info about inputs needed to plan incremenal compilation
public struct InputInfoMap {
  public static func populateOutOfDateMap(
    argsHash: String,
    lastBuildTime: Date,
    inputFiles: [TypedVirtualPath],
    buildRecordPath: VirtualPath,
    showIncrementalBuildDecisions: Bool
    ) -> Self? {
    stderrStream <<< "WARNING: incremental compilation not implemented yet\n"
    stderrStream.flush()
    return nil
  }
}
