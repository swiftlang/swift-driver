/// Triple - Helper for working with autoconf configuration names. For
/// historical reasons, we also call these 'triples' (they used to contain
/// exactly three fields).
///
/// Configuration names are strings in the canonical form:
///   ARCHITECTURE-VENDOR-OPERATING_SYSTEM
/// or
///   ARCHITECTURE-VENDOR-OPERATING_SYSTEM-ENVIRONMENT
///
/// This type is used for clients which want to support arbitrary
/// configuration names, but also want to implement certain special
/// behavior for particular configurations. This class isolates the mapping
/// from the components of the configuration name to well known IDs.
///
/// At its core the Triple class is designed to be a wrapper for a triple
/// string; the constructor does not change or normalize the triple string.
/// Clients that need to handle the non-canonical triples that users often
/// specify should use the normalize method.
///
/// See autoconf/config.guess for a glimpse into what configuration names
/// look like in practice.
///
/// This is a port of https://github.com/apple/swift-llvm/blob/stable/include/llvm/ADT/Triple.h
public struct Triple {

  /// The original triple string.
  public let triple: String

  /// The parsed arch.
  public let arch: Arch

  /// The parsed subarchitecture.
  public let subArch: SubArch

  /// The parsed vendor.
  public let vendor: Vendor

  /// The parsed OS.
  public let os: OS

  /// The parsed Environment type.
  public let environment: Environment

  /// The object format type.
  public let objectFormat: ObjectFormat

  public enum Arch {
    case unknown

    /// ARM (little endian): arm, armv.*, xscale
    case arm
    // ARM (big endian): armeb
    case armeb
    /// AArch64 (little endian): aarch64
    case aarch64
    /// AArch64 (big endian): aarch64_be
    case aarch64_be
    // AArch64 (little endian) ILP32: aarch64_32
    case aarch64_32
    /// ARC: Synopsys ARC
    case arc
    /// AVR: Atmel AVR microcontroller
    case avr
    /// eBPF or extended BPF or 64-bit BPF (little endian)
    case bpfel
    /// eBPF or extended BPF or 64-bit BPF (big endian)
    case bpfeb
    /// Hexagon: hexagon
    case hexagon
    /// MIPS: mips, mipsallegrex, mipsr6
    case mips
    /// MIPSEL: mipsel, mipsallegrexe, mipsr6el
    case mipsel
    // MIPS64: mips64, mips64r6, mipsn32, mipsn32r6
    case mips64
    // MIPS64EL: mips64el, mips64r6el, mipsn32el, mipsn32r6el
    case mips64el
    // MSP430: msp430
    case msp430
    // PPC: powerpc
    case ppc
    // PPC64: powerpc64, ppu
    case ppc64
    // PPC64LE: powerpc64le
    case ppc64le
    // R600: AMD GPUs HD2XXX - HD6XXX
    case r600
    // AMDGCN: AMD GCN GPUs
    case amdgcn
    // RISC-V (32-bit): riscv32
    case riscv32
    // RISC-V (64-bit): riscv64
    case riscv64
    // Sparc: sparc
    case sparc
    // Sparcv9: Sparcv9
    case sparcv9
    // Sparc: (endianness = little). NB: 'Sparcle' is a CPU variant
    case sparcel
    // SystemZ: s390x
    case systemz
    // TCE (http://tce.cs.tut.fi/): tce
    case tce
    // TCE little endian (http://tce.cs.tut.fi/): tcele
    case tcele
    // Thumb (little endian): thumb, thumbv.*
    case thumb
    // Thumb (big endian): thumbeb
    case thumbeb
    // X86: i[3-9]86
    case x86
    // X86-64: amd64, x86_64
    case x86_64
    // XCore: xcore
    case xcore
    // NVPTX: 32-bit
    case nvptx
    // NVPTX: 64-bit
    case nvptx64
    // le32: generic little-endian 32-bit CPU (PNaCl)
    case le32
    // le64: generic little-endian 64-bit CPU (PNaCl)
    case le64
    // AMDIL
    case amdil
    // AMDIL with 64-bit pointers
    case amdil64
    // AMD HSAIL
    case hsail
    // AMD HSAIL with 64-bit pointers
    case hsail64
    // SPIR: standard portable IR for OpenCL 32-bit version
    case spir
    // SPIR: standard portable IR for OpenCL 64-bit version
    case spir64
    // Kalimba: generic kalimba
    case kalimba
    // SHAVE: Movidius vector VLIW processors
    case shave
    // Lanai: Lanai 32-bit
    case lanai
    // WebAssembly with 32-bit pointers
    case wasm32
    // WebAssembly with 64-bit pointers
    case wasm64
    // 32-bit RenderScript
    case renderscript32
    // 64-bit RenderScript
    case renderscript64
  }

  public enum SubArch {
    case unknown
  }

  public enum Vendor {
    case unknown

    case apple
    case pc
    case scei
    case bgp
    case bgq
    case freescale
    case ibm
    case imaginationTechnologies
    case mipsTechnologies
    case nvidia
    case csr
    case myriad
    case amd
    case mesa
    case suse
    case openEmbedded
  }

  public enum OS {
    case unknown

    case ananas
    case cloudABI
    case darwin
    case dragonFly
    case freeBSD
    case fuchsia
    case ios
    case kfreebsd
    case linux
    case lv2
    case macosx
    case netbsd
    case openbsd
    case solaris
    case win32
    case haiku
    case minix
    case rtems
    case nacl
    case cnk
    case aix
    case cuda
    case nvcl
    case amdhsa
    case ps4
    case elfiamcu
    case tvos
    case watchos
    case mesa3d
    case contiki
    case amdpal
    case hermitcore
    case hurd
    case wasi
    case emscripten
  }

  public enum Environment {
    case unknown

    case eabihf
    case eabi
    case elfv1
    case elfv2
    case gnuabin32
    case gnuabi64
    case gnueabihf
    case gnueabi
    case gnux32
    case code16
    case gnu
    case android
    case musleabihf
    case musleabi
    case musl
    case msvc
    case itanium
    case cygnus
    case coreclr
    case simulator
    case macabi
  }

  public enum ObjectFormat {
    case unknown

    case coff
    case elf
    case macho
    case wasm
    case xcoff
  }

  public init(_ string: String) {
    self.triple = string

    let components = string.split(separator: "-", maxSplits: 3)

    self.arch = parseArch(components)
    self.subArch = parseSubArch(components)
    self.vendor = parseVendor(components)
    self.os = parseOS(components)
    self.environment = parseEnvironment(components)

    var objectFormat = parseObjectFormat(components)
    if objectFormat == .unknown {
      objectFormat = defaultObjectFormat(arch: arch, os: os)
    }
    self.objectFormat = objectFormat
  }
}

// MARK: - Parse Arch

private func parseArch(_ components: [Substring]) -> Triple.Arch {
  guard let archName = components.first else { return .unknown }

  var arch: Triple.Arch
  switch archName {
  // FIXME: Do we need to support these?
  case "i386", "i486", "i586", "i686":
    arch = .x86
  case "i786", "i886", "i986":
    arch = .x86
  case "amd64", "x86_64", "x86_64h":
    arch = .x86_64
  case "powerpc", "ppc", "ppc32":
    arch = .ppc
  case "powerpc64", "ppu", "ppc64":
    arch = .ppc64
  case "powerpc64le", "ppc64le":
    arch = .ppc64le
  case "xscale":
    arch = .arm
  case "xscaleeb":
    arch = .armeb
  case "aarch64":
    arch = .aarch64
  case "aarch64_be":
    arch = .aarch64_be
  case "aarch64_32":
    arch = .aarch64_32
  case "arc":
    arch = .arc
  case "arm64":
    arch = .aarch64
  case "arm64_32":
    arch = .aarch64_32
  case "arm":
    arch = .arm
  case "armeb":
    arch = .armeb
  case "thumb":
    arch = .thumb
  case "thumbeb":
    arch = .thumbeb
  case "avr":
    arch = .avr
  case "msp430":
    arch = .msp430
  case "mips", "mipseb", "mipsallegrex", "mipsisa32r6", "mipsr6":
    arch = .mips
  case "mipsel", "mipsallegrexel", "mipsisa32r6el", "mipsr6el":
    arch = .mipsel
  case "mips64", "mips64eb", "mipsn32", "mipsisa64r6", "mips64r6", "mipsn32r6":
    arch = .mips64
  case "mips64el", "mipsn32el", "mipsisa64r6el", "mips64r6el", "mipsn32r6el":
    arch = .mips64el
  case "r600":
    arch = .r600
  case "amdgcn":
    arch = .amdgcn
  case "riscv32":
    arch = .riscv32
  case "riscv64":
    arch = .riscv64
  case "hexagon":
    arch = .hexagon
  case "s390x", "systemz":
    arch = .systemz
  case "sparc":
    arch = .sparc
  case "sparcel":
    arch = .sparcel
  case "sparcv9", "sparc64":
    arch = .sparcv9
  case "tce":
    arch = .tce
  case "tcele":
    arch = .tcele
  case "xcore":
    arch = .xcore
  case "nvptx":
    arch = .nvptx
  case "nvptx64":
    arch = .nvptx64
  case "le32":
    arch = .le32
  case "le64":
    arch = .le64
  case "amdil":
    arch = .amdil
  case "amdil64":
    arch = .amdil64
  case "hsail":
    arch = .hsail
  case "hsail64":
    arch = .hsail64
  case "spir":
    arch = .spir
  case "spir64":
    arch = .spir64
  case _ where archName.starts(with: "kalimba"):
    arch = .kalimba
  case "lanai":
    arch = .lanai
  case "shave":
    arch = .shave
  case "wasm32":
    arch = .wasm32
  case "wasm64":
    arch = .wasm64
  case "renderscript32":
    arch = .renderscript32
  case "renderscript64":
    arch = .renderscript64
  default:
    arch = .unknown
  }

  // Some architectures require special parsing logic just to compute the
  // ArchType result.
  if arch == .unknown {
    if archName.starts(with: "arm") || archName.starts(with: "thumb") || archName.starts(with: "aarch64") {
      arch = parseARMArch(archName)
    }

    if archName.starts(with: "bpf") {
      arch = parseBPFArch(archName)
    }
  }

  return arch
}

private func parseARMArch<S: StringProtocol>(_ archName: S) -> Triple.Arch {
  fatalError("todo")
}

private func parseBPFArch<S: StringProtocol>(_ archName: S) -> Triple.Arch {
  fatalError("todo")
}

// MARK: - Parse SubArch

private func parseSubArch(_ components: [Substring]) -> Triple.SubArch {
  return .unknown
}

// MARK: - Parse Vendor

private func parseVendor(_ components: [Substring]) -> Triple.Vendor {
  guard components.count > 1 else { return .unknown }
  let vendorName = components[1]

  switch vendorName {
  case "apple":
    return .apple
  case "pc":
    return .pc
  case "scei":
    return .scei
  case "bgp":
    return .bgp
  case "bgq":
    return .bgq
  case "fsl":
    return .freescale
  case "ibm":
    return .ibm
  case "img":
    return .imaginationTechnologies
  case "mti":
    return .mipsTechnologies
  case "nvidia":
    return .nvidia
  case "csr":
    return .csr
  case "myriad":
    return .myriad
  case "amd":
    return .amd
  case "mesa":
    return .mesa
  case "suse":
    return .suse
  case "oe":
    return .openEmbedded
  default:
    return .unknown
  }
}

// MARK: - Parse OS

private func parseOS(_ components: [Substring]) -> Triple.OS {
  guard components.count > 2 else { return .unknown }
  let os = components[2]

  switch os {
  case _ where os.starts(with: "ananas"):
    return .ananas
  case _ where os.starts(with: "cloudabi"):
    return .cloudABI
  case _ where os.starts(with: "darwin"):
    return .darwin
  case _ where os.starts(with: "dragonfly"):
    return .dragonFly
  case _ where os.starts(with: "freebsd"):
    return .freeBSD
  case _ where os.starts(with: "fuchsia"):
    return .fuchsia
  case _ where os.starts(with: "ios"):
    return .ios
  case _ where os.starts(with: "kfreebsd"):
    return .kfreebsd
  case _ where os.starts(with: "linux"):
    return .linux
  case _ where os.starts(with: "lv2"):
    return .lv2
  case _ where os.starts(with: "macos"):
    return .macosx
  case _ where os.starts(with: "netbsd"):
    return .netbsd
  case _ where os.starts(with: "openbsd"):
    return .openbsd
  case _ where os.starts(with: "solaris"):
    return .solaris
  case _ where os.starts(with: "win32"):
    return .win32
  case _ where os.starts(with: "windows"):
    return .win32
  case _ where os.starts(with: "haiku"):
    return .haiku
  case _ where os.starts(with: "minix"):
    return .minix
  case _ where os.starts(with: "rtems"):
    return .rtems
  case _ where os.starts(with: "nacl"):
    return .nacl
  case _ where os.starts(with: "cnk"):
    return .cnk
  case _ where os.starts(with: "aix"):
    return .aix
  case _ where os.starts(with: "cuda"):
    return .cuda
  case _ where os.starts(with: "nvcl"):
    return .nvcl
  case _ where os.starts(with: "amdhsa"):
    return .amdhsa
  case _ where os.starts(with: "ps4"):
    return .ps4
  case _ where os.starts(with: "elfiamcu"):
    return .elfiamcu
  case _ where os.starts(with: "tvos"):
    return .tvos
  case _ where os.starts(with: "watchos"):
    return .watchos
  case _ where os.starts(with: "mesa3d"):
    return .mesa3d
  case _ where os.starts(with: "contiki"):
    return .contiki
  case _ where os.starts(with: "amdpal"):
    return .amdpal
  case _ where os.starts(with: "hermit"):
    return .hermitcore
  case _ where os.starts(with: "hurd"):
    return .hurd
  case _ where os.starts(with: "wasi"):
    return .wasi
  case _ where os.starts(with: "emscripten"):
    return .emscripten
  default:
    return .unknown
  }
}

// MARK: - Parse Environment

private func parseEnvironment(_ components: [Substring]) -> Triple.Environment {
  if components.count > 3 {
    let env = components[3]
    switch env {
    case _ where env.starts(with: "eabihf"):
      return .eabihf
    case _ where env.starts(with: "eabi"):
      return .eabi
    case _ where env.starts(with: "elfv1"):
      return .elfv1
    case _ where env.starts(with: "elfv2"):
      return .elfv2
    case _ where env.starts(with: "gnuabin32"):
      return .gnuabin32
    case _ where env.starts(with: "gnuabi64"):
      return .gnuabi64
    case _ where env.starts(with: "gnueabihf"):
      return .gnueabihf
    case _ where env.starts(with: "gnueabi"):
      return .gnueabi
    case _ where env.starts(with: "gnux32"):
      return .gnux32
    case _ where env.starts(with: "code16"):
      return .code16
    case _ where env.starts(with: "gnu"):
      return .gnu
    case _ where env.starts(with: "android"):
      return .android
    case _ where env.starts(with: "musleabihf"):
      return .musleabihf
    case _ where env.starts(with: "musleabi"):
      return .musleabi
    case _ where env.starts(with: "musl"):
      return .musl
    case _ where env.starts(with: "msvc"):
      return .msvc
    case _ where env.starts(with: "itanium"):
      return .itanium
    case _ where env.starts(with: "cygnus"):
      return .cygnus
    case _ where env.starts(with: "coreclr"):
      return .coreclr
    case _ where env.starts(with: "simulator"):
      return .simulator
    case _ where env.starts(with: "macabi"):
      return .macabi
    default:
      return .unknown
    }
  } else if let firstComponent = components.first {
    switch firstComponent {
    case _ where firstComponent.hasPrefix("mipsn32"):
      return .gnuabin32
    case _ where firstComponent.hasPrefix("mips64"):
      return .gnuabi64
    case _ where firstComponent.hasPrefix("mipsisa64"):
      return .gnuabi64
    case _ where firstComponent.hasPrefix("mipsisa32"):
      return .gnu
    case "mips", "mipsel", "mipsr6", "mipsr6el":
      return .gnu
    default:
      return .unknown
    }
  }
  return .unknown
}

// MARK: - Parse Object Format

private func parseObjectFormat(_ components: [Substring]) -> Triple.ObjectFormat {
  guard components.count > 3 else { return .unknown }
  let env = components[3]

  switch env {
  // "xcoff" must come before "coff" because of the order-dependendent pattern matching.
  case _ where env.hasSuffix("xcoff"):
    return .xcoff
  case _ where env.hasSuffix("coff"):
    return .coff
  case _ where env.hasSuffix("elf"):
    return .elf
  case _ where env.hasSuffix("macho"):
    return .macho
  case _ where env.hasSuffix("wasm"):
    return .wasm
  default:
    return .unknown
  }
}

private func defaultObjectFormat(arch: Triple.Arch, os: Triple.OS) -> Triple.ObjectFormat {
  switch arch {
    case .unknown: fallthrough
    case .aarch64: fallthrough
    case .aarch64_32: fallthrough
    case .arm: fallthrough
    case .thumb: fallthrough
    case .x86: fallthrough
    case .x86_64:
      if os.isDarwin {
        return .macho
      } else if os.isWindows {
        return .coff
      }
      return .elf

    case .aarch64_be: fallthrough
    case .arc: fallthrough
    case .amdgcn: fallthrough
    case .amdil: fallthrough
    case .amdil64: fallthrough
    case .armeb: fallthrough
    case .avr: fallthrough
    case .bpfeb: fallthrough
    case .bpfel: fallthrough
    case .hexagon: fallthrough
    case .lanai: fallthrough
    case .hsail: fallthrough
    case .hsail64: fallthrough
    case .kalimba: fallthrough
    case .le32: fallthrough
    case .le64: fallthrough
    case .mips: fallthrough
    case .mips64: fallthrough
    case .mips64el: fallthrough
    case .mipsel: fallthrough
    case .msp430: fallthrough
    case .nvptx: fallthrough
    case .nvptx64: fallthrough
    case .ppc64le: fallthrough
    case .r600: fallthrough
    case .renderscript32: fallthrough
    case .renderscript64: fallthrough
    case .riscv32: fallthrough
    case .riscv64: fallthrough
    case .shave: fallthrough
    case .sparc: fallthrough
    case .sparcel: fallthrough
    case .sparcv9: fallthrough
    case .spir: fallthrough
    case .spir64: fallthrough
    case .systemz: fallthrough
    case .tce: fallthrough
    case .tcele: fallthrough
    case .thumbeb: fallthrough
    case .xcore:
      return .elf

    case .ppc: fallthrough
    case .ppc64:
      if os.isDarwin {
        return .macho
      } else if os == .aix {
        return .xcoff
      }
      return .elf

    case .wasm32: fallthrough
    case .wasm64:
      return .wasm
  }
}

extension Triple.OS {

  public var isWindows: Bool {
    self == .win32
  }

  public var isAIX: Bool {
    self == .aix
  }

  /// isMacOSX - Is this a Mac OS X triple. For legacy reasons, we support both
  /// "darwin" and "osx" as OS X triples.
  public var isMacOSX: Bool {
    self == .darwin || self == .macosx
  }

  /// Is this an iOS triple.
  /// Note: This identifies tvOS as a variant of iOS. If that ever
  /// changes, i.e., if the two operating systems diverge or their version
  /// numbers get out of sync, that will need to be changed.
  /// watchOS has completely different version numbers so it is not included.
  public var isiOS: Bool {
    self == .ios || isTvOS
  }

  /// Is this an Apple tvOS triple.
  public var isTvOS: Bool {
    self == .tvos
  }

  /// Is this an Apple watchOS triple.
  public var isWatchOS: Bool {
    self == .watchos
  }

  /// isOSDarwin - Is this a "Darwin" OS (OS X, iOS, or watchOS).
  public var isDarwin: Bool {
    isMacOSX || isiOS || isWatchOS
  }
}
