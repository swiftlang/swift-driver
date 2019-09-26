# Swift compiler driver

A reimplementation of the Swift compiler's "driver", which coordinates Swift compilation,
linking, etc., in Swift. Why reimplement the Swift compiler driver?

* Swift is way more fun to code in than C++
* Swift's current driver code is a bit messy and could use major refactoring
* Swift's driver is standalone, relatively small (~10kloc) and in a separate process from the main body of the compiler, so it's an easy target for reimplementation
