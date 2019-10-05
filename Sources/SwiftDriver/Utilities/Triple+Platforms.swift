public enum DarwinPlatform: RawRepresentable, Hashable {
  public enum Environment: Hashable {
    // FIXME: iOS should also have a state for macCatalyst. This
    // should probably be modeled as a separate type to preserve
    // exhaustivity checking for tvOS and watchOS.
    case device
    case simulator
  }
  
  case macOS
  case iOS(Environment)
  case tvOS(Environment)
  case watchOS(Environment)
  
  func with(_ environment: Environment) -> DarwinPlatform? {
    switch self {
    case .macOS:
      guard environment == .device else { return nil }
      return .macOS
    case .iOS:
      return .iOS(environment)
    case .tvOS:
      return .tvOS(environment)
    case .watchOS:
      return .watchOS(environment)
    }
  }
  
  public init?(rawValue: String) {
    switch rawValue {
    case "macosx":
      self = .macOS
    case "iphoneos":
      self = .iOS(.device)
    case "iphonesimulator":
      self = .iOS(.simulator)
    case "appletvos":
      self = .tvOS(.device)
    case "appletvsimulator":
      self = .tvOS(.simulator)
    case "watchos":
      self = .watchOS(.device)
    case "watchsimulator":
      self = .watchOS(.simulator)
    default:
      return nil
    }
  }
  
  public var rawValue: String {
    switch self {
    case .macOS:
      return "macosx"
    case .iOS(.device):
      return "iphoneos"
    case .iOS(.simulator):
      return "iphonesimulator"
    case .tvOS(.device):
      return "appletvos"
    case .tvOS(.simulator):
      return "appletvsimulator"
    case .watchOS(.device):
      return "watchos"
    case .watchOS(.simulator):
      return "watchsimulator"
    }
  }
}

extension Triple {
  public var _isSimulatorEnvironment: Bool {
    // FIXME: transitional, this should eventually stop testing arch, and
    // switch to only checking the -environment field.
    return environment == .simulator || arch == .x86 || arch == .x86_64
  }
  
  /// Returns the OS version equivalent for the given platform.
  public func version(for platform: DarwinPlatform) -> Triple.Version {
    switch platform {
    case .macOS:
      return _macOSVersion!
    case .iOS, .tvOS:
      return _iOSVersion
    case .watchOS:
      return _watchOSVersion
    }
  }
  
  public var darwinPlatform: DarwinPlatform? {
    func makeEnvironment() -> DarwinPlatform.Environment {
      _isSimulatorEnvironment ? .simulator : .device
    }
    switch os {
    case .darwin, .macosx:
      return .macOS
    case .ios:
      return .iOS(makeEnvironment())
    case .watchos:
      return .watchOS(makeEnvironment())
    case .tvos:
      return .tvOS(makeEnvironment())
    default:
      return nil
    }
  }
  
  public var platformName: String? {
    switch os {
    case nil:
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
        fatalError("unsupported Windows environment: \(environment, or: "nil")")
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
      darwinPlatform : darwinPlatform.with(.device)!
    switch platform {
    case .macOS: return "osx"
    case .iOS(.device): return "ios"
    case .iOS(.simulator): return "iossim"
    case .tvOS(.device): return "tvos"
    case .tvOS(.simulator): return "tvossim"
    case .watchOS(.device): return "watchos"
    case .watchOS(.simulator): return "watchossim"
    }
  }
}

extension Triple {
  /// Represents the availability of a feature that is supported on some platforms
  /// and versions, but not all. For Darwin versions, the version numbers provided
  /// should be the version where the feature was added or the change was
  /// introduced, because all version checks are in the form of
  /// `tripleVersion >= featureVersion`.
  ///
  /// - SeeAlso: `Triple.supports(_:)`
  public struct FeatureAvailability {
    public let macOS: Triple.Version?
    public let iOS: Triple.Version?
    public let tvOS: Triple.Version?
    public let watchOS: Triple.Version?
    
    // TODO: We should have linux, windows, etc.
    public let nonDarwin: Bool
    
    /// Describes the availability of a feature that is supported on multiple platforms,
    /// but is tied to a particular version.
    ///
    /// Each version parameter is `Optional`; a `nil` value means the feature is
    /// not supported on any version of that platform. Use `Triple.Version.zero`
    /// for a feature that is available in all versions.
    ///
    /// If `tvOS` availability is omitted, it will be set to be the same as `iOS`.
    public init(
      macOS: Triple.Version?,
      iOS: Triple.Version?,
      tvOS: Triple.Version?,
      watchOS: Triple.Version?,
      nonDarwin: Bool = false
    ) {
      self.macOS = macOS
      self.iOS = iOS
      self.tvOS = tvOS
      self.watchOS = watchOS
      self.nonDarwin = nonDarwin
    }
    
    /// Describes the availability of a feature that is supported on multiple platforms,
    /// but is tied to a particular version.
    ///
    /// Each version parameter is `Optional`; a `nil` value means the feature is
    /// not supported on any version of that platform. Use `Triple.Version.zero`
    /// for a feature that is available in all versions.
    ///
    /// If `tvOS` availability is omitted, it will be set to be the same as `iOS`.
    public init(
      macOS: Triple.Version?,
      iOS: Triple.Version?,
      watchOS: Triple.Version?,
      nonDarwin: Bool = false
    ) {
      self.init(macOS: macOS, iOS: iOS, tvOS: iOS, watchOS: watchOS)
    }
    
    /// Returns the version when the feature was introduced on the specified Darwin
    /// platform, or `nil` if the feature has not been introduced there.
    public subscript(darwinPlatform: DarwinPlatform) -> Triple.Version? {
      switch darwinPlatform {
      case .macOS:
        return macOS
      case .iOS:
        return iOS
      case .tvOS:
        return tvOS
      case .watchOS:
        return watchOS
      }
    }
  }
  
  /// Checks whether the triple supports the specified feature.
  public func supports(_ feature: FeatureAvailability) -> Bool {
    guard let darwinPlatform = darwinPlatform else {
      return feature.nonDarwin
    }
    guard let introducedVersion = feature[darwinPlatform] else {
      return false
    }
    
    return version(for: darwinPlatform) >= introducedVersion
  }
}

extension Triple.FeatureAvailability {
  static let swiftInTheOS = Self(
    // macOS 10.14.4 contains a copy of Swift, but the linker will still use an
    // rpath-based install name until 10.15.
    macOS: Triple.Version(10, 15, 0),
    iOS: Triple.Version(12, 2, 0),
    watchOS: Triple.Version(5, 2, 0),
    nonDarwin: false
  )
  
  /// Minimum OS version with a fully compatible ObjC runtime. Below these versions,
  /// we will link libarclite.
  static let compatibleObjCRuntime = Self(
    macOS: Triple.Version(10, 11, 0),
    iOS: Triple.Version(9, 0, 0),
    watchOS: .zero
  )
  // When updating the versions listed here, please record the most recent
  // feature being depended on and when it was introduced:
  //
  // - Make assigning 'nil' to an NSMutableDictionary subscript delete the
  //   entry, like it does for Swift.Dictionary, rather than trap.
}
