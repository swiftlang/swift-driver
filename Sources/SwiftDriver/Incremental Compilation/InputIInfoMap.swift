import TSCBasic
import TSCUtility
import Foundation

/// Holds the info about inputs needed to plan incremenal compilation
public struct InputInfoMap {
  public static func populateOutOfDateMap(
    argsHash: String,
    lastBuildTime: Date,
    inputFiles: [TypedVirtualPath],
    buildRecordPath: AbsolutePath,
    showIncrementalBuildDecisions: Bool
  ) -> Self? {
    do {
      try localFileSystem.readFileContents(buildRecordPath)
    }
    catch {
      if showIncrementalBuildDecisions {
        stderrStream <<<
        "Incremental compilation could not read build record (\(error.localizedDescription)).\n"
      }
      
      return nil
    }
    stderrStream <<< "WARNING: incremental compilation not implemented yet\n"
    stderrStream.flush()
    return nil
  }
}
