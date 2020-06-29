//===--------------- Triple+Platforms.swift - Swift Platform Triples ------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Represents any of the "Apple" platforms handled by `DarwinToolchain`.
/// This boils down a lot of complicated logic about different variants and
/// environments into a straightforward, tightly-modeled type that can be
/// switched over.
///
/// `DarwinPlatform` does not contain version information, but
/// `Triple.version(for:)` retrieves a version based on the
/// corresponding `DarwinPlatform`.
public enum DarwinPlatform: Hashable {
  /// macOS, corresponding to the `macosx`, `macos`, and `darwin` OS names.
  case macOS

  /// iOS, corresponding to the `ios` and `iphoneos` OS names. This does not
  /// match tvOS.
  case iOS(Environment)

  /// tvOS, corresponding to the `tvos` OS name.
  case tvOS(EnvironmentWithoutCatalyst)

  /// watchOS, corresponding to the `watchos` OS name.
  case watchOS(EnvironmentWithoutCatalyst)

  /// The most general form of environment information attached to a
  /// `DarwinPlatform`.
  ///
  /// The environment is a variant of the platform like `device` or `simulator`.
  /// Not all platforms support all values of environment. This type is a superset of
  /// all the environments available on any case.
  public enum Environment: Hashable {
    case device
    case simulator
    case catalyst

    var withoutCatalyst: EnvironmentWithoutCatalyst? {
      switch self {
      case .device:
        return .device
      case .simulator:
        return .simulator
      case .catalyst:
        return nil
      }
    }
  }

  public enum EnvironmentWithoutCatalyst: Hashable {
    case device
    case simulator
  }

  /// Returns the same platform, but with the environment replaced by
  /// `environment`. Returns `nil` if `environment` is not valid
  /// for `self`.
  func with(_ environment: Environment) -> DarwinPlatform? {
    switch self {
    case .macOS:
      guard environment == .device else { return nil }
      return .macOS
    case .iOS:
      return .iOS(environment)
    case .tvOS:
      guard let withoutCatalyst = environment.withoutCatalyst else { return nil }
      return .tvOS(withoutCatalyst)
    case .watchOS:
    guard let withoutCatalyst = environment.withoutCatalyst else { return nil }
      return .watchOS(withoutCatalyst)
    }
  }

  /// The platform name, i.e. the name clang uses to identify this platform in its
  /// resource directory.
  public var platformName: String {
    switch self {
    case .macOS:
      return "macosx"
    case .iOS(.device):
      return "iphoneos"
    case .iOS(.simulator):
      return "iphonesimulator"
    case .iOS(.catalyst):
      return "maccatalyst"
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

  /// The name used to identify this platform in compiler_rt file names.
  public var libraryNameSuffix: String {
    switch self {
    case .macOS:
      return "osx"
    case .iOS(.device):
      return "ios"
    case .iOS(.simulator):
      return "iossim"
    case .iOS(.catalyst):
        return "osx"
    case .tvOS(.device):
      return "tvos"
    case .tvOS(.simulator):
      return "tvossim"
    case .watchOS(.device):
      return "watchos"
    case .watchOS(.simulator):
      return "watchossim"
    }
  }
}

extension Triple {
  /// If this is a Darwin device platform, should it be inferred to be a device simulator?
  public var _isSimulatorEnvironment: Bool {
    // FIXME: transitional, this should eventually stop testing arch, and
    // switch to only checking the -environment field.
    return environment == .simulator || arch == .x86 || arch == .x86_64
  }

  /// Returns the OS version equivalent for the given platform, converting and
  /// defaulting various representations.
  ///
  /// - Parameter compatibilityPlatform: Overrides the platform to be fetched.
  ///   For compatibility reasons, you sometimes have to e.g. pass an argument with a macOS
  ///   version number even when you're building watchOS code. This parameter specifies the
  ///   platform you need a version number for; the method will then return an arbitrary but
  ///   suitable version number for `compatibilityPlatform`.
  ///
  /// - Precondition: `self` must be able to provide a version for `compatibilityPlatform`.
  ///   Not all combinations are valid; in particular, you cannot fetch a watchOS version
  ///   from an iOS/tvOS triple or vice versa.
  public func version(for compatibilityPlatform: DarwinPlatform? = nil)
    -> Triple.Version
  {
    switch compatibilityPlatform ?? darwinPlatform! {
    case .macOS:
      return _macOSVersion!
    case .iOS, .tvOS:
      return _iOSVersion
    case .watchOS:
      return _watchOSVersion
    }
  }

  /// Returns the `DarwinPlatform` for this triple, or `nil` if it is a non-Darwin
  /// platform.
  ///
  /// - SeeAlso: DarwinPlatform
  public var darwinPlatform: DarwinPlatform? {
    func makeEnvironment() -> DarwinPlatform.EnvironmentWithoutCatalyst {
      _isSimulatorEnvironment ? .simulator : .device
    }
    switch os {
    case .darwin, .macosx:
      return .macOS
    case .ios:
      if isMacCatalyst {
        return .iOS(.catalyst)
      } else if _isSimulatorEnvironment {
        return .iOS(.simulator)
      } else {
        return .iOS(.device)
      }
    case .watchos:
      return .watchOS(makeEnvironment())
    case .tvos:
      return .tvOS(makeEnvironment())
    default:
      return nil
    }
  }

  /// The platform name, i.e. the name clang uses to identify this target in its
  /// resource directory.
  ///
  /// - Parameter conflatingDarwin: If true, all Darwin platforms will be
  ///   identified as just `darwin` instead of by individual platform names.
  ///   Defaults to `false`.
  public func platformName(conflatingDarwin: Bool = false) -> String? {
    switch os {
    case nil:
      fatalError("unknown OS")
    case .darwin, .macosx, .ios, .tvos, .watchos:
      guard let darwinPlatform = darwinPlatform else {
        fatalError("unsupported darwin platform kind?")
      }
      return conflatingDarwin ? "darwin" : darwinPlatform.platformName

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
      self.init(macOS: macOS, iOS: iOS, tvOS: iOS, watchOS: watchOS,
                nonDarwin: nonDarwin)
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

  /// Checks whether the triple supports the specified feature, i.e., the feature
  /// has been introduced by the OS and version indicated by the triple.
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
  /// Linking `libarclite` is unnecessary for triples supporting this feature.
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
