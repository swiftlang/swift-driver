
extension Option {
  public static let driverPrintGraphviz: Option = Option("-driver-print-graphviz", .flag, attributes: [.helpHidden, .doesNotAffectIncrementalBuild], helpText: "Write the job graph as a graphviz file", group: .internalDebug)

  public static var extraOptions: [Option] {
    return [
      Option.driverPrintGraphviz
    ]
  }
}
