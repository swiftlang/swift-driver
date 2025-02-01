//===------------------------ SwiftScan.swift -----------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import protocol Foundation.CustomNSError
import var Foundation.NSLocalizedDescriptionKey

#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

internal enum Loader {
}

extension Loader {
  internal enum Error: Swift.Error {
    case `open`(String)
    case close(String)
  }
}

extension Loader.Error: CustomNSError {
  public var errorUserInfo: [String:Any] {
    return [NSLocalizedDescriptionKey: "\(self)"]
  }
}

#if !os(Windows)
extension Loader {
  private static func error() -> String? {
    if let error: UnsafeMutablePointer<CChar> = dlerror() {
      return String(cString: error)
    }
    return nil
  }
}
#endif

extension Loader {
  internal final class Handle {
#if os(Windows)
    typealias ValueType = HMODULE
#else
    typealias ValueType = UnsafeMutableRawPointer
#endif

    fileprivate var value: ValueType?

    init(value: ValueType) {
      self.value = value
    }

    deinit {
      precondition(value == nil,
                   "Handle must be closed or explicitly leaked before deinit")
    }

    public func close() throws {
      if let handle = self.value {
#if os(Windows)
        guard FreeLibrary(handle) else {
          throw Loader.Error.close("FreeLibrary failure: \(GetLastError())")
        }
#else
        guard dlclose(handle) == 0 else {
          throw Loader.Error.close(Loader.error() ?? "unknown error")
        }
#endif
      }
      self.value = nil
    }

    public func leak() {
      self.value = nil
    }
  }
}

extension Loader {
  internal struct Flags: RawRepresentable, OptionSet {
    public var rawValue: Int32

    public init(rawValue: Int32) {
      self.rawValue = rawValue
    }
  }
}

#if !os(Windows)
extension Loader.Flags {
    public static var lazy: Loader.Flags {
      Loader.Flags(rawValue: RTLD_LAZY)
    }

    public static var now: Loader.Flags {
      Loader.Flags(rawValue: RTLD_NOW)
    }

    public static var local: Loader.Flags {
      Loader.Flags(rawValue: RTLD_LOCAL)
    }

    public static var global: Loader.Flags {
      Loader.Flags(rawValue: RTLD_GLOBAL)
    }

    // Platform-specific flags
#if canImport(Darwin)
    public static var first: Loader.Flags {
      Loader.Flags(rawValue: RTLD_FIRST)
    }

    public static var deepBind: Loader.Flags {
      Loader.Flags(rawValue: 0)
    }
#else
    public static var first: Loader.Flags {
      Loader.Flags(rawValue: 0)
    }

#if os(Linux) && canImport(Glibc)
    public static var deepBind: Loader.Flags {
      Loader.Flags(rawValue: RTLD_DEEPBIND)
    }
#else
    public static var deepBind: Loader.Flags {
      Loader.Flags(rawValue: 0)
    }
#endif
#endif
}
#endif

extension Loader {
  public static func load(_ path: String?, mode: Flags) throws -> Handle {
#if os(Windows)
    guard let handle = path?.withCString(encodedAs: UTF16.self, LoadLibraryW) else {
      throw Loader.Error.open("LoadLibraryW failure: \(GetLastError())")
    }
#else
    guard let handle = dlopen(path, mode.rawValue) else {
      throw Loader.Error.open(Loader.error() ?? "unknown error")
    }
#endif
    return Handle(value: handle)
  }

  public static func getSelfHandle(mode: Flags) throws -> Handle {
#if os(Windows)
    guard let handle = GetModuleHandleW(nil) else  {
      throw Loader.Error.open("GetModuleHandleW(nil) failure: \(GetLastError())")
    }
#else
    guard let handle = dlopen(nil, mode.rawValue) else {
      throw Loader.Error.open(Loader.error() ?? "unknown error")
    }
#endif
    return Handle(value: handle)
  }

  public static func lookup<T>(symbol: String, in module: Handle) -> T? {
#if os(Windows)
    guard let pointer = GetProcAddress(module.value!, symbol) else {
      return nil
    }
#else
    guard let pointer = dlsym(module.value!, symbol) else {
      return nil
    }
#endif
    return unsafeBitCast(pointer, to: T.self)
  }

  public static func unload(_ handle: Handle) throws {
    try handle.close()
  }
}
