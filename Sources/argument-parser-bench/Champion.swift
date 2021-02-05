import SwiftOptions

var ChampionCounter = 0

struct Champion {
  let optionTable: OptionTable
  var parsedOptions: ParsedOptions
  
  init(_ arguments: [String]) throws {
    self.optionTable = OptionTable()
    self.parsedOptions = try optionTable.parse(arguments, for: .batch)

    assert(parsedOptions.getLastArgument(.indexStorePath)?.asSingle == "/Users/nate/Projects/swift-argument-parser/.build/x86_64-apple-macosx/debug/index/store")
    assert(parsedOptions.allInputs.count > 0)
    assert(parsedOptions.getLastArgument(.target)?.asSingle == "x86_64-apple-macosx10.10")
    assert(true == parsedOptions.contains(.colorDiagnostics))
    
    ChampionCounter += 1
  }
}
