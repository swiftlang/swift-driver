let driverKind = DriverKind.interactive
let options = OptionTable(driverKind: driverKind)
options.printHelp(usage: driverKind.usage, title: driverKind.title, includeHidden: false)
