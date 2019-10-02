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
  public let objectFormatType: ObjectFormat

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
      // NIOSII: nios2
      case nios2
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
    case unknown
  }

  public enum OS {
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
    case unknown
  }

  public enum Environment {
    case unknown
  }

  public enum ObjectFormat {
    case unknown
  }

  public init(_ string: String) {
    self.triple = string

    let components = string.split(separator: "-", maxSplits: 3)

    self.arch = parseArch(components)
    self.subArch = parseSubArch(components)
    self.vendor = parseVendor(components)
    self.os = parseOS(components)
    self.environment = parseEnvironment(components)
    self.objectFormatType = .unknown
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
  return .unknown
}

// MARK: - Parse Object Format Type

private func parseObjectFormatType(_ components: [Substring]) -> Triple.SubArch {
  return .unknown
}
