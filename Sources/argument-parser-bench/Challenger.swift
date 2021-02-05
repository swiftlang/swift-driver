import ArgumentParser
import ArgumentParserOptions

var ChallengerCounter = 0

struct Challenger: ParsableCommand {
  @OptionGroup var o: O
  @OptionGroup var codeFormatting: codeFormatting
  @OptionGroup var debugCrash: debugCrash
  @OptionGroup var g: g
  @OptionGroup var `internal`: `internal`
  @OptionGroup var internalDebug: internalDebug
  @OptionGroup var linkerOption: linkerOption
  @OptionGroup var modes: modes
  @OptionGroup var general: General

  func run() throws {
    assert(general.indexStorePath == "/Users/nate/Projects/swift-argument-parser/.build/x86_64-apple-macosx/debug/index/store")
    assert(general.INPUT.count > 0)
    assert(general.target == "x86_64-apple-macosx10.10")
    assert(true == general.colorDiagnostics)
    
    ChallengerCounter += 1
  }
}
