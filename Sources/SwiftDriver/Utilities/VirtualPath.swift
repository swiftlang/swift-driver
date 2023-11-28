//===--------------- VirtualPath.swift - Swift Virtual Paths --------------===//
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

import struct Foundation.Data
import struct Foundation.TimeInterval
import class Dispatch.DispatchQueue

#if canImport(Darwin)
import Darwin
#endif

import enum TSCBasic.SystemError
import func TSCBasic.resolveSymlinks
import protocol TSCBasic.FileSystem
import protocol TSCBasic.WritableByteStream
import struct TSCBasic.AbsolutePath
import struct TSCBasic.ByteString
import struct TSCBasic.FileInfo
import struct TSCBasic.RelativePath
import var TSCBasic.localFileSystem

/// A virtual path.
public enum VirtualPath: Hashable {
  private static var pathCache = PathCache()

  private static var temporaryFileStore = TemporaryFileStore()

  /// A relative path that has not been resolved based on the current working
  /// directory.
  case relative(RelativePath)

  /// An absolute path in the file system.
  case absolute(AbsolutePath)

  /// Standard input
  case standardInput

  /// Standard output
  case standardOutput

  /// We would like to direct clients to use the temporary file creation utilities `createUniqueTemporaryFile`, etc.
  /// To ensure temporary files are unique.
  /// TODO: If/When Swift gains enum access control, we can prohibit direct instantiation of temporary file cases,
  /// e.g. `private(init) case temporary(RelativePath)`.
  /// A temporary file with the given name.
  case temporary(RelativePath)
  /// A temporary file with the given name and contents.
  case temporaryWithKnownContents(RelativePath, Data)
  /// A temporary file that holds a list of paths.
  case fileList(RelativePath, FileList)

  /// Form a virtual path which may be either absolute or relative.
  public init(path: String) throws {
    self = try Self.pathCache[Self.pathCache.intern(path)]
  }

  /// The name of the path for presentation purposes.
  public var name: String { description }

  /// The extension of this path, for relative or absolute paths.
  public var `extension`: String? {
    switch self {
    case .relative(let path), .temporary(let path),
         .temporaryWithKnownContents(let path, _), .fileList(let path, _):
      return path.extension
    case .absolute(let path):
      return path.extension
    case .standardInput, .standardOutput:
      return nil
    }
  }

  /// Whether this virtual path is to a temporary.
  public var isTemporary: Bool {
    switch self {
    case .relative, .absolute, .standardInput, .standardOutput:
      return false
    case .temporary, .temporaryWithKnownContents, .fileList:
      return true
    }
  }

  public var absolutePath: AbsolutePath? {
    switch self {
    case let .absolute(absolutePath):
      return absolutePath
    case .relative, .temporary, .temporaryWithKnownContents, .fileList, .standardInput, .standardOutput:
      return nil
    }
  }

  public var relativePath: RelativePath? {
    guard case .relative(let relativePath) = self else { return nil }
    return relativePath
  }

  /// If the path is some kind of temporary file, returns the `RelativePath`
  /// representing its name.
  public var temporaryFileName: RelativePath? {
    switch self {
    case .temporary(let name),
         .fileList(let name, _),
         .temporaryWithKnownContents(let name, _):
      return name
    case .absolute, .relative, .standardInput, .standardOutput:
      return nil
    }
  }

  /// Retrieve the basename of the path.
  public var basename: String {
    switch self {
    case .absolute(let path):
      return path.basename
    case .relative(let path), .temporary(let path), .temporaryWithKnownContents(let path, _), .fileList(let path, _):
      return path.basename
    case .standardInput, .standardOutput:
      return ""
    }
  }

  /// Retrieve the basename of the path without the extension.
  public var basenameWithoutExt: String {
    switch self {
    case .absolute(let path):
      return path.basenameWithoutExt
    case .relative(let path), .temporary(let path), .temporaryWithKnownContents(let path, _), .fileList(let path, _):
      return path.basenameWithoutExt
    case .standardInput, .standardOutput:
      return ""
    }
  }

  /// Retrieve the path to the parent directory.
  public var parentDirectory: VirtualPath {
    switch self {
    case .absolute(let path):
      return .absolute(path.parentDirectory)
    case .relative(let path):
      return .relative(try! RelativePath(validating: path.dirname))
    case .temporary(let path), .temporaryWithKnownContents(let path, _):
      return .temporary(try! RelativePath(validating: path.dirname))
    case .fileList(let path, _):
      return .temporary(try! RelativePath(validating: path.dirname))
    case .standardInput, .standardOutput:
      assertionFailure("Can't get directory of stdin/stdout")
      return self
    }
  }

  /// Returns the virtual path with an additional literal component appended.
  ///
  /// This should not be used with `.standardInput` or `.standardOutput`.
  public func appending(component: String) -> VirtualPath {
    switch self {
    case .absolute(let path):
      return .absolute(path.appending(component: component))
    case .relative(let path):
      return .relative(path.appending(component: component))
    case .temporary(let path):
      return .temporary(path.appending(component: component))
    case let .temporaryWithKnownContents(path, contents):
      return .temporaryWithKnownContents(path.appending(component: component), contents)
    case .fileList(let path, let content):
      return .fileList(path.appending(component: component), content)
    case .standardInput, .standardOutput:
      assertionFailure("Can't append path component to standard in/out")
      return self
    }
  }

  public func appending(components: String...) -> VirtualPath {
    switch self {
    case .absolute(let path):
      return .absolute(path.appending(components: components))
    case .relative(let path):
      return .relative(path.appending(components: components))
    case .temporary(let path):
      return .temporary(path.appending(components: components))
    case let .temporaryWithKnownContents(path, contents):
      return .temporaryWithKnownContents(path.appending(components: components), contents)
    case .fileList(let path, let content):
      return .fileList(path.appending(components: components), content)
    case .standardInput, .standardOutput:
      assertionFailure("Can't append path component to standard in/out")
      return self
    }
  }

  /// Returns the virtual path with an additional suffix appended to base name.
  ///
  /// This should not be used with `.standardInput` or `.standardOutput`.
  public func appendingToBaseName(_ suffix: String) throws -> VirtualPath {
    switch self {
    case let .absolute(path):
      return .absolute(try AbsolutePath(validating: path.pathString + suffix))
    case let .relative(path):
      return .relative(try RelativePath(validating: path.pathString + suffix))
    case let .temporary(path):
      return .temporary(try RelativePath(validating: path.pathString + suffix))
    case let .temporaryWithKnownContents(path, contents):
      return .temporaryWithKnownContents(try RelativePath(validating: path.pathString + suffix), contents)
    case let .fileList(path, content):
      return .fileList(try RelativePath(validating: path.pathString + suffix), content)
    case .standardInput, .standardOutput:
      assertionFailure("Can't append path component to standard in/out")
      return self
    }
  }

  public static func == (lhs: VirtualPath, rhs: VirtualPath) -> Bool {
    switch (lhs, rhs) {
    case (.standardOutput, .standardOutput), (.standardInput, .standardInput):
      return true
    case (.standardOutput, _), (.standardInput, _), (_, .standardOutput), (_, .standardInput):
      return false
    default:
      return lhs.description == rhs.description
    }
  }
}

extension VirtualPath.Handle: Codable {
  public func encode(to encoder: Encoder) throws {
    return try VirtualPath.lookup(self).encode(to: encoder)
  }

  public init(from decoder: Decoder) throws {
    let vp = try VirtualPath(from: decoder)
    switch vp {
    case .standardOutput:
      self = .standardOutput
    case .standardInput:
      self = .standardInput
    default:
      self = vp.intern()
    }
  }
}

// MARK: Path Interning

extension VirtualPath {
  /// Retrieves a shared `VirtualPath.Handle` for the given raw `path` string,
  /// which may be absolute or relative.
  ///
  /// - Parameter path: The path to the file.
  /// - Throws: `PathValidationError` if the given `path` is not valid.
  /// - Returns: A `VirtualPath.Handle` to a validated `VirtualPath`
  public static func intern(path: String) throws -> VirtualPath.Handle {
    return try Self.pathCache.intern(path)
  }

  /// Resolves a shared `VirtualPath.Handle` to a particular `VirtualPath`.
  ///
  /// - Parameter handle: The handle to resolve.
  /// - Returns: A `VirtualPath` instance for the given handle.
  public static func lookup(_ handle: VirtualPath.Handle) -> VirtualPath {
    return Self.pathCache[handle]
  }

  /// Creates or retrieves the handle corresponding to an existing virtual path.
  ///
  /// This method is always going to be faster than `VirutalPath.init(path:)`
  /// or `VirtualPath.intern(path:)` because no further validation of the
  /// path string is necessary.
  public func intern() -> VirtualPath.Handle {
    switch self {
    case .standardInput:
      return .standardInput
    case .standardOutput:
      return .standardOutput
    default:
      return Self.pathCache.intern(virtualPath: self)
    }
  }

  /// Computes the cache key for this virtual path.
  ///
  /// This hash key ensures that absolute and relative path entries constructed
  /// from strings will always resolve to interned constants with a matching
  /// canonical path string. However, temporaries and filelists will never hash
  /// equal to a relative or absolute path to ensure that the extra data
  /// that comes along with these kinds of virtual paths is not lost.
  fileprivate var cacheKey: String {
    switch self {
    case .relative(let path):
      return path.pathString
    case .absolute(let path):
      return path.pathString
    case .temporary(let path):
      // N.B. Mangle in a discrimintor for temporaries so they intern apart
      // from normal kinds of paths.
      return "temporary:" + path.pathString
    case .temporaryWithKnownContents(let path, _):
      return "temporaryWithKnownContents:" + path.pathString
    case .fileList(let path, _):
      return "fileList:" + path.pathString
    case .standardInput, .standardOutput:
      fatalError("\(self) does not have a cache key")
    }
  }
}

extension VirtualPath {
  /// A handle to a `VirtualPath` that is much lighter-weight and faster to
  /// pass around, hash, and compare.
  ///
  /// `VirtualPath` has a particularly expensive implementation of `Hashable`
  /// that makes using it as the key in hashed collections expensive as well. By
  /// using a `VirtualPath.Handle`, hashing costs are amortized. Additionally,
  /// `VirtualPath.init(path:)` is quite an expensive operation. Interned
  /// `VirtualPath.Handle` instances represent fully-validated paths, so sharing
  /// in the global path table ensures we only pay the cost at most once per
  /// path string.
  public struct Handle {
    fileprivate var core: Int

    fileprivate init(_ core: Int) {
      self.core = core
    }

    public static let standardOutput = Handle(-1)
    public static let standardInput = Handle(-2)
#if os(Windows)
    public static let null = try! VirtualPath(path: "nul").intern()
#else
    public static let null = try! VirtualPath(path: "/dev/null").intern()
#endif
  }

  /// An implementation of a concurrent path cache.
  private final class PathCache {
    private var uniquer: [String: VirtualPath.Handle]
    private var table: [VirtualPath]
    private let queue: DispatchQueue

    init() {
      self.uniquer = [String: VirtualPath.Handle]()
      self.table = [VirtualPath]()
      self.queue = DispatchQueue(label: "com.apple.swift.driver.path-cache", qos: .userInteractive, attributes: .concurrent)

      self.uniquer.reserveCapacity(256)
      self.table.reserveCapacity(256)
    }

    fileprivate func intern(_ key: String) throws -> VirtualPath.Handle {
      return try self.queue.sync(flags: .barrier) {
        guard let idx = self.uniquer[key] else {
          let path: VirtualPath
          // The path representation does not properly handle paths on all
          // platforms.  On Windows, we often see an empty key which we would
          // like to treat as being the relative path to cwd.
          if key.isEmpty {
            path = .relative(try RelativePath(validating: "."))
          } else if let absolute = try? AbsolutePath(validating: key) {
            path = .absolute(absolute)
          } else {
            let relative = try RelativePath(validating: key)
            path = .relative(relative)
          }
          if let existing = self.uniquer[path.cacheKey] {
            // If there's an entry for the canonical path for this key, we just
            // need to vend its handle.
            self.uniquer[key] = existing
            return existing
          } else {
            // Otherwise we need to add an entry for the key and its canonical
            // path.
            let nextSlot = self.table.count
            self.uniquer[path.cacheKey] = .init(nextSlot)
            self.uniquer[key] = .init(nextSlot)
            self.table.append(path)
            return .init(nextSlot)
          }
        }
        assert(idx.core >= 0, "Produced invalid index \(idx) for path \(key)")
        return idx
      }
    }

    fileprivate func intern(virtualPath path: VirtualPath) -> VirtualPath.Handle {
      return self.queue.sync(flags: .barrier) {
        guard let idx = self.uniquer[path.cacheKey] else {
          let nextSlot = self.table.count
          self.uniquer[path.cacheKey] = .init(nextSlot)
          self.table.append(path)
          return .init(nextSlot)
        }
        assert(idx.core >= 0, "Produced invalid index \(idx) for path \(path)")
        return idx
      }
    }

    fileprivate func lookupHandle(for path: VirtualPath) -> VirtualPath.Handle? {
      switch path {
      case .standardInput:
        return .standardInput
      case .standardOutput:
        return .standardOutput
      default:
        return self.queue.sync {
          return self.uniquer[path.cacheKey]
        }
      }
    }

    fileprivate subscript(key: VirtualPath.Handle) -> VirtualPath {
      switch key {
      case .standardInput:
        return .standardInput
      case .standardOutput:
        return .standardOutput
      default:
        return self.queue.sync {
          return self.table[key.core]
        }
      }
    }
  }
}

// MARK: Temporary File Creation

/// Most client contexts require temporary files they request to be unique (e.g. auxiliary compile outputs).
/// This extension provides a set of utilities to create unique (within driver context) relative paths to temporary files.
/// Clients are still allowed to instantiate `.temporary` `VirtualPath` values directly because of our inability to specify
/// enum case access control, but are discouraged from doing so.
extension VirtualPath {
  public static func createUniqueTemporaryFile(_ path: RelativePath) throws -> VirtualPath {
    let uniquedRelativePath = try getUniqueTemporaryPath(for: path)
    return .temporary(uniquedRelativePath)
  }

  public static func createUniqueTemporaryFileWithKnownContents(_ path: RelativePath, _ data: Data)
  throws -> VirtualPath {
    let uniquedRelativePath = try getUniqueTemporaryPath(for: path)
    return .temporaryWithKnownContents(uniquedRelativePath, data)
  }

  public static func createUniqueFilelist(_ path: RelativePath, _ fileList: FileList)
  throws -> VirtualPath {
    let uniquedRelativePath = try getUniqueTemporaryPath(for: path)
    return .fileList(uniquedRelativePath, fileList)
  }

  private static func getUniqueTemporaryPath(for path: RelativePath) throws -> RelativePath {
    let uniquedBaseName = Self.temporaryFileStore.getUniqueFilename(for: path.basenameWithoutExt)
    // Avoid introducing the the leading dot
    let dirName = path.dirname == "." ? "" : path.dirname
    let fileExtension = path.extension.map { ".\($0)" } ?? ""
    return try RelativePath(validating: dirName + uniquedBaseName + fileExtension)
  }

  /// A cache of created temporary files
  private final class TemporaryFileStore {
    private var uniqueFileCountDict: [String: Int]
    private var queue: DispatchQueue

    init() {
      self.uniqueFileCountDict = [String: Int]()
      self.queue = DispatchQueue(label: "com.apple.swift.driver.temp-file-store",
                                 qos: .userInteractive)
    }

    fileprivate func getUniqueFilename(for temporaryPathStr: String) -> String {
      return self.queue.sync() {
        let newCount: Int
        if let previouslySeenCount = uniqueFileCountDict[temporaryPathStr] {
          newCount = previouslySeenCount + 1
        } else {
          newCount = 1
        }
        uniqueFileCountDict[temporaryPathStr] = newCount
        return "\(temporaryPathStr)-\(newCount)"
      }
    }

    // Used for testing purposes only
    fileprivate func reset() {
      return self.queue.sync() {
        uniqueFileCountDict.removeAll()
      }
    }
  }

  // Reset the temporary file store, for testing purposes only
  @_spi(Testing) public static func resetTemporaryFileStore() {
    Self.temporaryFileStore.reset()
  }
}

extension VirtualPath.Handle: CustomStringConvertible {
  public var description: String {
    VirtualPath.lookup(self).description
  }
}

extension VirtualPath.Handle: Equatable {}
extension VirtualPath.Handle: Hashable {}

extension VirtualPath: Codable {
  private enum CodingKeys: String, CodingKey {
    case relative, absolute, standardInput, standardOutput, temporary,
         temporaryWithKnownContents, fileList
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .relative(let a1):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .relative)
      try unkeyedContainer.encode(a1)
    case .absolute(let a1):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .absolute)
      try unkeyedContainer.encode(a1)
    case .standardInput:
      _ = container.nestedUnkeyedContainer(forKey: .standardInput)
    case .standardOutput:
      _ = container.nestedUnkeyedContainer(forKey: .standardOutput)
    case .temporary(let a1):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .temporary)
      try unkeyedContainer.encode(a1)
    case let .temporaryWithKnownContents(path, contents):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .temporaryWithKnownContents)
      try unkeyedContainer.encode(path)
      try unkeyedContainer.encode(contents)
    case .fileList(let path, let fileList):
      var unkeyedContainer = container.nestedUnkeyedContainer(forKey: .fileList)
      try unkeyedContainer.encode(path)
      try unkeyedContainer.encode(fileList)
    }
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard let key = values.allKeys.first(where: values.contains) else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Did not find a matching key"))
    }
    switch key {
    case .relative:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(RelativePath.self)
      self = .relative(a1)
    case .absolute:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(AbsolutePath.self)
      self = .absolute(a1)
    case .standardInput:
      self = .standardInput
    case .standardOutput:
      self = .standardOutput
    case .temporary:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let a1 = try unkeyedValues.decode(RelativePath.self)
      self = .temporary(a1)
    case .temporaryWithKnownContents:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let path = try unkeyedValues.decode(RelativePath.self)
      let contents = try unkeyedValues.decode(Data.self)
      self = .temporaryWithKnownContents(path, contents)
    case .fileList:
      var unkeyedValues = try values.nestedUnkeyedContainer(forKey: key)
      let path = try unkeyedValues.decode(RelativePath.self)
      let fileList = try unkeyedValues.decode(FileList.self)
      self = .fileList(path, fileList)
    }
  }
}

/// A wrapper for easier decoding of absolute or relative VirtualPaths from strings.
public struct TextualVirtualPath: Codable, Hashable {
  public var path: VirtualPath.Handle

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    path = try VirtualPath.intern(path: container.decode(String.self))
  }

  public init(path: VirtualPath.Handle) {
    self.path = path
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch VirtualPath.lookup(self.path) {
    case .absolute(let path):
      try container.encode(path.pathString)
    case .relative(let path):
      try container.encode(path.pathString)
    case .temporary, .temporaryWithKnownContents, .standardInput,
         .standardOutput, .fileList:
      preconditionFailure("Path does not have a round-trippable textual representation")
    }
  }

  internal var description: String { VirtualPath.lookup(path).description }
}

extension VirtualPath: CustomStringConvertible {
  public var description: String {
    switch self {
    case .relative(let path):
      return path.pathString

    case .absolute(let path):
      return path.pathString

    case .standardInput, .standardOutput:
      return "-"

    case .temporary(let path), .temporaryWithKnownContents(let path, _),
         .fileList(let path, _):
      return path.pathString
    }
  }
}

extension VirtualPath: CustomDebugStringConvertible {
  public var debugDescription: String {
    switch self {
    case .relative(let path):
      return ".relative(\(path.pathString))"
    case .absolute(let path):
      return ".absolute(\(path.pathString))"
    case .standardInput:
      return ".standardInput"
    case .standardOutput:
      return ".standardOutput"
    case .temporary(let path):
      return ".temporary(\(path.pathString))"
    case .temporaryWithKnownContents(let path, _):
      return ".temporaryWithKnownContents(\(path.pathString))"
    case .fileList(let path, _):
      return ".fileList(\(path.pathString))"
    }
  }
}

extension VirtualPath {
  /// Replace the extension of the given path with a new one based on the
  /// specified file type.
  public func replacingExtension(with fileType: FileType) throws -> VirtualPath {
    switch self {
    case let .absolute(path):
      return .absolute(try AbsolutePath(validating: path.pathString.withoutExt(path.extension).appendingFileTypeExtension(fileType)))
    case let .relative(path):
      return .relative(try RelativePath(validating: path.pathString.withoutExt(path.extension).appendingFileTypeExtension(fileType)))
    case let .temporary(path):
      return .temporary(try RelativePath(validating: path.pathString.withoutExt(path.extension).appendingFileTypeExtension(fileType)))
    case let .temporaryWithKnownContents(path, contents):
      return .temporaryWithKnownContents(try RelativePath(validating: path.pathString.withoutExt(path.extension).appendingFileTypeExtension(fileType)), contents)
    case let .fileList(path, content):
      return .fileList(try RelativePath(validating: path.pathString.withoutExt(path.extension).appendingFileTypeExtension(fileType)), content)
    case .standardInput, .standardOutput:
      return self
    }
  }
}

extension VirtualPath {
  /// Resolve a relative path into an absolute one, if possible.
  public func resolvedRelativePath(base: AbsolutePath) -> VirtualPath {
    guard case let .relative(relPath) = self else { return self }
    return .absolute(.init(base, relPath))
  }
}

private extension String {
  func withoutExt(_ ext: String?) -> String {
    if let ext = ext {
      return String(dropLast(ext.count + 1))
    } else {
      return self
    }
  }
}

enum FileSystemError: Swift.Error {
  case noCurrentWorkingDirectory
  case cannotResolveTempPath(RelativePath)
  case cannotResolveStandardInput
  case cannotResolveStandardOutput
}

extension TSCBasic.FileSystem {
  private func resolvingVirtualPath<T>(
    _ path: VirtualPath,
    apply f: (AbsolutePath) throws -> T
  ) throws -> T {
    switch path {
    case let .absolute(absPath):
      return try f(absPath)
    case let .relative(relPath):
      guard let cwd = currentWorkingDirectory else {
        throw FileSystemError.noCurrentWorkingDirectory
      }
      return try f(.init(cwd, relPath))
    case let .temporary(relPath), let .temporaryWithKnownContents(relPath, _),
         let .fileList(relPath, _):
      throw FileSystemError.cannotResolveTempPath(relPath)
    case .standardInput:
      throw FileSystemError.cannotResolveStandardInput
    case .standardOutput:
      throw FileSystemError.cannotResolveStandardOutput
    }
  }

  @_spi(Testing) public func readFileContents(_ path: VirtualPath) throws -> ByteString {
    try resolvingVirtualPath(path, apply: readFileContents)
  }

  func writeFileContents(_ path: VirtualPath, bytes: ByteString, atomically: Bool) throws {
    try resolvingVirtualPath(path) { absolutePath in
      try self.writeFileContents(absolutePath, bytes: bytes, atomically: atomically)
    }
  }

  func writeFileContents(_ path: VirtualPath, body: (WritableByteStream) -> Void) throws {
    try resolvingVirtualPath(path) { absolutePath in
      try self.writeFileContents(absolutePath, body: body)
    }
  }

  @_spi(Testing) public func removeFileTree(_ path: VirtualPath) throws {
    try resolvingVirtualPath(path) { absolutePath in
      try self.removeFileTree(absolutePath)
    }
  }

  func getFileInfo(_ path: VirtualPath) throws -> TSCBasic.FileInfo {
    try resolvingVirtualPath(path, apply: getFileInfo)
  }

  func exists(_ path: VirtualPath) throws -> Bool {
    try resolvingVirtualPath(path, apply: exists)
  }

  /// Retrieves the last modification time of the file referenced at the given path.
  ///
  /// If the given file path references a symbolic link, the modification time for the *linked file*
  /// - not the symlink itself - is returned.
  ///
  /// - Parameter file: The path to a file.
  /// - Throws: `SystemError` if the underlying `stat` operation fails.
  /// - Returns: A `Date` value containing the last modification time.
  public func lastModificationTime(for file: VirtualPath) throws -> TimePoint {
    try resolvingVirtualPath(file) { path in
      #if canImport(Darwin)
      var s = Darwin.stat()
      let err = stat(path.pathString, &s)
      guard err == 0 else {
        throw SystemError.stat(errno, path.pathString)
      }
      return TimePoint(seconds: UInt64(s.st_mtimespec.tv_sec),
                       nanoseconds: UInt32(s.st_mtimespec.tv_nsec))
      #else
      // `getFileInfo` is going to ask Foundation to stat this path, and
      // Foundation is always going to use `lstat` to do so. This is going to
      // do the wrong thing for symbolic links, for which we always want to
      // retrieve the mod time of the underlying file. This makes build systems
      // that regenerate lots of symlinks but do not otherwise alter the
      // contents of files - like Bazel - quite happy.
      let path = try resolveSymlinks(path)
      #if os(Windows)
      // The NT epoch is 1601, so we need to add a correction factor to bridge
      // between Foundation.Date's insistence on using the Mac epoch time of
      // 2001 as its reference date.
      //
      // This factor is a coarse approximation of the difference between
      // (Jan 1, 1970 at midnight GMT) and (Jan 1, 1601 at midnight GMT).
      //
      // DO NOT RELY ON THIS VALUE
      //
      // This whole thing needs to be replaced by APIs that traffic in values
      // derived from uncorrected Windows clocks.
      let correction: TimeInterval = 11_644_473_600.0
      let unixReferenceDate = try localFileSystem.getFileInfo(path).modTime.timeIntervalSince1970
      let interval: TimeInterval = unixReferenceDate + correction
      #else
      let interval: TimeInterval = try localFileSystem.getFileInfo(path).modTime.timeIntervalSince1970
      #endif
      return TimePoint(seconds: UInt64(interval.rounded(.down)), nanoseconds: 0)
      #endif
    }
  }
}

