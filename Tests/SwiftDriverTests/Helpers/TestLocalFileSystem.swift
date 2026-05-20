//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import TSCBasic

/// A file system wrapper that allows overriding the current working directory
/// on a per-instance basis, enabling concurrent tests to each have their own
/// CWD without mutating the process-global working directory.
///
/// All file system operations are delegated to `localFileSystem`. Only
/// `currentWorkingDirectory` and `changeCurrentWorkingDirectory` are
/// intercepted to use the instance-local override.
final class TestLocalFileSystem: FileSystem {
  private nonisolated(unsafe) var _cwd: AbsolutePath?

  init(cwd: AbsolutePath? = nil) {
    _cwd = cwd
  }

  var currentWorkingDirectory: AbsolutePath? {
    _cwd ?? localFileSystem.currentWorkingDirectory
  }

  func changeCurrentWorkingDirectory(to path: AbsolutePath) throws {
    _cwd = path
  }

  // MARK: - Delegated to localFileSystem

  func exists(_ path: AbsolutePath, followSymlink: Bool) -> Bool {
    localFileSystem.exists(path, followSymlink: followSymlink)
  }

  func isDirectory(_ path: AbsolutePath) -> Bool {
    localFileSystem.isDirectory(path)
  }

  func isFile(_ path: AbsolutePath) -> Bool {
    localFileSystem.isFile(path)
  }

  func isExecutableFile(_ path: AbsolutePath) -> Bool {
    localFileSystem.isExecutableFile(path)
  }

  func isSymlink(_ path: AbsolutePath) -> Bool {
    localFileSystem.isSymlink(path)
  }

  func isReadable(_ path: AbsolutePath) -> Bool {
    localFileSystem.isReadable(path)
  }

  func isWritable(_ path: AbsolutePath) -> Bool {
    localFileSystem.isWritable(path)
  }

  func itemReplacementDirectories(for path: AbsolutePath) throws -> [AbsolutePath] {
    try localFileSystem.itemReplacementDirectories(for: path)
  }

  @available(*, deprecated, message: "use `hasAttribute(_:_:)` instead")
  func hasQuarantineAttribute(_ path: AbsolutePath) -> Bool {
    localFileSystem.hasQuarantineAttribute(path)
  }

  func hasAttribute(_ name: FileSystemAttribute, _ path: AbsolutePath) -> Bool {
    localFileSystem.hasAttribute(name, path)
  }

  func getDirectoryContents(_ path: AbsolutePath) throws -> [String] {
    try localFileSystem.getDirectoryContents(path)
  }

  var homeDirectory: AbsolutePath {
    get throws { try localFileSystem.homeDirectory }
  }

  var cachesDirectory: AbsolutePath? {
    localFileSystem.cachesDirectory
  }

  var tempDirectory: AbsolutePath {
    get throws { try localFileSystem.tempDirectory }
  }

  func createDirectory(_ path: AbsolutePath) throws {
    try localFileSystem.createDirectory(path)
  }

  func createDirectory(_ path: AbsolutePath, recursive: Bool) throws {
    try localFileSystem.createDirectory(path, recursive: recursive)
  }

  func createSymbolicLink(_ path: AbsolutePath, pointingAt destination: AbsolutePath, relative: Bool) throws {
    try localFileSystem.createSymbolicLink(path, pointingAt: destination, relative: relative)
  }

  func readFileContents(_ path: AbsolutePath) throws -> ByteString {
    try localFileSystem.readFileContents(path)
  }

  func writeFileContents(_ path: AbsolutePath, bytes: ByteString) throws {
    try localFileSystem.writeFileContents(path, bytes: bytes)
  }

  func writeFileContents(_ path: AbsolutePath, bytes: ByteString, atomically: Bool) throws {
    try localFileSystem.writeFileContents(path, bytes: bytes, atomically: atomically)
  }

  func removeFileTree(_ path: AbsolutePath) throws {
    try localFileSystem.removeFileTree(path)
  }

  func chmod(_ mode: FileMode, path: AbsolutePath, options: Set<FileMode.Option>) throws {
    try localFileSystem.chmod(mode, path: path, options: options)
  }

  func copy(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
    try localFileSystem.copy(from: sourcePath, to: destinationPath)
  }

  func move(from sourcePath: AbsolutePath, to destinationPath: AbsolutePath) throws {
    try localFileSystem.move(from: sourcePath, to: destinationPath)
  }

  func getFileInfo(_ path: AbsolutePath) throws -> FileInfo {
    try localFileSystem.getFileInfo(path)
  }
}
