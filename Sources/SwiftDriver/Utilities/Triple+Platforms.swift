public enum DarwinPlatform: String{
  case macOS = "macosx"
  case iOS = "iphoneos"
  case iPhoneSimulator = "iphonesimulator"
  case tvOS = "appletvos"
  case appleTVSimulator = "appletvsimulator"
  case watchOS = "watchos"
  case watchSimulator = "watchsimulator"

  public var nonSimulatorPlatform: DarwinPlatform {
    switch self {
    case .macOS: return .macOS
    case .iOS, .iPhoneSimulator: return .iOS
    case .tvOS, .appleTVSimulator: return .tvOS
    case .watchOS, .watchSimulator: return .watchOS
    }
  }
}

extension Triple {
  public var isSimulatorEnvironment: Bool {
    // FIXME: transitional, this should eventually stop testing arch, and
    // switch to only checking the -environment field.
    return environment == .simulator || arch == .x86 || arch == .x86_64
  }

  public var darwinPlatform: DarwinPlatform? {
    switch os {
    case .darwin, .macosx: return .macOS
    case .ios: return isSimulatorEnvironment ? .iPhoneSimulator : .iOS
    case .watchos: return isSimulatorEnvironment ? .watchSimulator : .watchOS
    case .tvos: return isSimulatorEnvironment ? .appleTVSimulator : .tvOS
    default: return nil
    }
  }
  public var platformName: String? {
    switch os {
    case .unknown:
      fatalError("unknown OS")
    case .darwin, .macosx, .ios, .tvos, .watchos:
      guard let darwinPlatform = darwinPlatform else {
        fatalError("unsupported darwin platform kind?")
      }
      return darwinPlatform.rawValue
    case .linux:
      return environment == .android ? "android" : "linux"
    case .freeBSD:
      return "freebsd"
    case .win32:
      switch environment {
      case .cygnus:
        return "cygwin"
      case .gnu:
        return "mingw"
      case .msvc, .itanium:
        return "windows"
      default:
        fatalError("unsupported Windows environment: \(environment)")
      }
    case .ps4:
      return "ps4"
    case .haiku:
      return "haiku"

    // Explicitly spell out the remaining cases to force a compile error when
    // Triple updates
    case .ananas, .cloudABI, .dragonFly, .fuchsia, .kfreebsd, .lv2, .netbsd,
         .openbsd, .solaris, .minix, .rtems, .nacl, .cnk, .aix, .cuda, .nvcl,
         .amdhsa, .elfiamcu, .mesa3d, .contiki, .amdpal, .hermitcore, .hurd,
         .wasi, .emscripten:
      return nil
    }
  }

  func darwinLibraryNameSuffix(distinguishSimulator: Bool = true) -> String? {
    guard let darwinPlatform = darwinPlatform else { return nil }
    let platform = distinguishSimulator ?
      darwinPlatform : darwinPlatform.nonSimulatorPlatform
    switch platform {
    case .macOS: return "osx"
    case .iOS: return "ios"
    case .iPhoneSimulator: return "iossim"
    case .tvOS: return "tvos"
    case .appleTVSimulator: return "tvossim"
    case .watchOS: return "watchos"
    case .watchSimulator: return "watchossim"
    }
  }

  var requiresRPathForSwiftInTheOS: Bool {
    if os.isMacOSX {
      // macOS 10.14.4 contains a copy of Swift, but the linker will still use an
      // rpath-based install name until 10.15.
      return osVersion() < Version(10, 15, 0)
    } else if os.isiOS {
      return iOSVersion() < Version(12, 2, 0)
    } else if os.isWatchOS {
      return watchOSVersion() < Version(5, 2, 0)
    }

    // Other platforms don't have Swift installed as part of the OS by default.
    return false
  }
}
