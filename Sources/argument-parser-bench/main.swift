import ArgumentParser
import Dispatch

let N = 200

func time(_ name: String, body: () throws -> ()) {
  let start = DispatchTime.now().uptimeNanoseconds
  for _ in 1...N {
    try! body()
  }
  let end = DispatchTime.now().uptimeNanoseconds

  let seconds = Double(end - start) / Double(1_000_000_000)
  print("\(name): \(seconds)")
}

time("ArgumentParser") {
  var command = try Challenger.parseAsRoot(arguments)
  try command.run()
  
  assert(N == ChallengerCounter)
}

time("SwiftOptions") {
  let current = try Champion(arguments)
  
  assert(N == ChampionCounter)
}

