//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import class Foundation.NSCondition
import class Foundation.NSLock
import class Foundation.OperationQueue
import class Foundation.Thread
import struct Foundation.Date
import struct Foundation.TimeInterval

import class TSCBasic.DiagnosticsEngine
import struct TSCBasic.Diagnostic
import typealias TSCBasic.ProcessEnvironmentBlock

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

/// A client of the GNU make jobserver: a token pool shared by every process in
/// a build, bounding how many jobs run at once across all of them.
///
/// One job may run on the implicit token the parent spent to launch this
/// process; each further concurrent job needs a token from the pool, written
/// back when it finishes. Every acquire must be paired with a release, or the
/// pool shrinks for the rest of the build.
///
/// See "POSIX Jobserver Interaction" in the GNU make manual.
final class JobServer {

  /// The right to run one job.
  struct Token {
    fileprivate enum Kind {
      /// The slot this process owns because its parent spent a token to launch
      /// it. Never written back to the pool.
      case implicit
#if os(Windows)
      /// A count of one taken from the pool semaphore.
      case semaphore
#else
      /// A byte taken from the pool. The same byte must be written back, so it
      /// is carried here.
      case byte(UInt8)
#endif
    }
    fileprivate let kind: Kind
  }

#if os(Windows)
  /// The named semaphore backing the pool.
  private let semaphore: HANDLE

  /// Signalled when the implicit token is returned or the pool shuts down.
  private let wakeupEvent: HANDLE
#else
  /// The read and write ends of the pool. For the FIFO transport these are the
  /// same descriptor, opened read-write.
  private let readFD: CInt
  private let writeFD: CInt

  /// Whether we opened the descriptors ourselves, and so may close them and set
  /// their status flags. Inherited descriptors share an open file description
  /// with every other process in the build, so setting `O_NONBLOCK` on them
  /// would change how *those* processes see the pool.
  private let ownsDescriptors: Bool

  /// A self-pipe that wakes a waiter when the implicit token is returned or the
  /// pool shuts down -- neither of which makes the pool itself readable.
  private let wakeupReadFD: CInt
  private let wakeupWriteFD: CInt
#endif

  /// Guards `isImplicitTokenAvailable` and `isShutDown`.
  private let lock = NSLock()
  private var isImplicitTokenAvailable = true
  private var isShutDown = false

  /// How long a wait blocks before rechecking state. Only a backstop against a
  /// missed wakeup, since token returns and shutdown signal the waiter directly.
  private static let pollIntervalMilliseconds: CInt = 100

  private static let fifoPrefix = "fifo:"

  /// Creates a client for the jobserver advertised in `MAKEFLAGS`, or returns
  /// `nil` if this build has not opted in to jobserver participation (via the
  /// `-experimental-use-gnu-jobserver` swiftc flag) or is not
  /// running under a jobserver at all.
  static func detect(env: ProcessEnvironmentBlock,
                     enabled: Bool,
                     diagnosticsEngine: DiagnosticsEngine) -> JobServer? {
    // Opt-in: without the flag nothing changes, even when a pool is advertised.
    guard enabled else { return nil }
    guard let makeFlags = env["MAKEFLAGS"],
          let auth = parseAuthentication(from: makeFlags) else {
      // Not running under a jobserver: leave concurrency to `-j`, as before.
      return nil
    }
    guard let jobServer = JobServer(auth: auth) else {
      // A pool was advertised but unreachable: GNU make closes the descriptors
      // unless the recipe that ran us was treated as recursive.
      diagnosticsEngine.emit(.warning_jobserver_unavailable)
      return nil
    }
    return jobServer
  }

  /// Extracts the jobserver authentication string from the value of
  /// `MAKEFLAGS`, or returns `nil` if it does not advertise a pool.
  ///
  /// GNU make 4.2 renamed `--jobserver-fds` to `--jobserver-auth`; the old
  /// spelling is still what make 3.81 (macOS's `/usr/bin/make`) emits, so both
  /// are accepted. The last occurrence wins.
  static func parseAuthentication(from makeFlags: String) -> String? {
    let prefixes = ["--jobserver-auth=", "--jobserver-fds="]
    var authentication: String? = nil
    for flag in makeFlags.split(separator: " ") {
      for prefix in prefixes where flag.hasPrefix(prefix) {
        authentication = String(flag.dropFirst(prefix.count))
      }
    }
    return authentication
  }

  /// Returns `env` with the jobserver authentication stripped from `MAKEFLAGS`,
  /// leaving the rest of the value intact.
  ///
  /// The compiler frontends we launch are not jobserver clients -- their copies
  /// of the pool descriptors are closed on exec -- so advertising the pool to
  /// them would only invite a stray client to drain it. This mirrors how make
  /// omits the pool from a recipe it does not treat as recursive.
  static func censoringAuthentication(in env: ProcessEnvironmentBlock) -> ProcessEnvironmentBlock {
    guard let makeFlags = env["MAKEFLAGS"] else { return env }
    let prefixes = ["--jobserver-auth=", "--jobserver-fds="]
    let kept = makeFlags.split(separator: " ").filter { flag in
      !prefixes.contains { flag.hasPrefix($0) }
    }
    var censored = env
    censored["MAKEFLAGS"] = kept.isEmpty ? nil : kept.joined(separator: " ")
    return censored
  }

#if os(Windows)
  /// Not private: the tests construct a client over a pipe they control.
  init?(auth: String) {
    let access = DWORD(SEMAPHORE_MODIFY_STATE | SYNCHRONIZE)
    guard let semaphore = auth.withCString(encodedAs: UTF16.self, {
      OpenSemaphoreW(access, false, $0)
    }) else {
      return nil
    }
    // Auto-resetting, initially unsignalled.
    guard let wakeupEvent = CreateEventW(nil, false, false, nil) else {
      CloseHandle(semaphore)
      return nil
    }
    self.semaphore = semaphore
    self.wakeupEvent = wakeupEvent
  }

  deinit {
    CloseHandle(semaphore)
    CloseHandle(wakeupEvent)
  }

  private func signalWakeup() {
    _ = SetEvent(wakeupEvent)
  }
#else
  /// Not private: the tests construct a client over a pipe they control.
  init?(auth: String) {
    var wakeup: [CInt] = [0, 0]
    guard pipe(&wakeup) == 0 else { return nil }
    for fd in wakeup {
      _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
      _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }
    self.wakeupReadFD = wakeup[0]
    self.wakeupWriteFD = wakeup[1]

    if auth.hasPrefix(Self.fifoPrefix) {
      // GNU make 4.4+ can hand out a named FIFO instead of inherited
      // descriptors. Opening it read-write keeps `open` from blocking on a
      // missing peer and keeps reads from ever seeing end-of-file.
      let path = String(auth.dropFirst(Self.fifoPrefix.count))
      let fd = path.withCString { open($0, O_RDWR | O_NONBLOCK | O_CLOEXEC) }
      guard fd >= 0 else {
        close(wakeup[0])
        close(wakeup[1])
        return nil
      }
      self.readFD = fd
      self.writeFD = fd
      self.ownsDescriptors = true
    } else {
      let descriptors = auth.split(separator: ",")
      guard descriptors.count == 2,
            let readFD = CInt(descriptors[0]),
            let writeFD = CInt(descriptors[1]),
            fcntl(readFD, F_GETFD) != -1,
            fcntl(writeFD, F_GETFD) != -1 else {
        close(wakeup[0])
        close(wakeup[1])
        return nil
      }
      // Our children are compiler frontends rather than jobserver clients, so
      // keep the pool out of their descriptor tables.
      _ = fcntl(readFD, F_SETFD, FD_CLOEXEC)
      _ = fcntl(writeFD, F_SETFD, FD_CLOEXEC)
      self.readFD = readFD
      self.writeFD = writeFD
      self.ownsDescriptors = false
    }
  }

  deinit {
    if ownsDescriptors {
      close(readFD)
    }
    close(wakeupReadFD)
    close(wakeupWriteFD)
  }

  private func signalWakeup() {
    var byte: UInt8 = 0
    // A full self-pipe already means a wakeup is pending, so a failure here is
    // not interesting.
    _ = retryOnInterrupt { write(wakeupWriteFD, &byte, 1) }
  }

  private func drainWakeup() {
    var buffer = [UInt8](repeating: 0, count: 64)
    while true {
      let count = buffer.withUnsafeMutableBytes { raw in
        retryOnInterrupt { read(wakeupReadFD, raw.baseAddress, raw.count) }
      }
      if count <= 0 { break }
    }
  }
#endif

  /// Blocks until a slot to run a job in is available, returning `nil` if the
  /// pool was shut down while waiting.
  func acquire() -> Token? {
    if let token = takeImplicitToken() {
      return token
    }
    return acquireFromPool()
  }

  /// Claims the free slot this process owns, if it is not already in use.
  /// Returns `nil` once the pool has shut down.
  private func takeImplicitToken() -> Token? {
    lock.lock()
    defer { lock.unlock() }
    guard !isShutDown, isImplicitTokenAvailable else { return nil }
    isImplicitTokenAvailable = false
    return Token(kind: .implicit)
  }

  /// Returns a token to the pool. Must be called for every token `acquire`
  /// handed out, including when the job it was taken for failed.
  func release(_ token: Token) {
    switch token.kind {
    case .implicit:
      lock.lock()
      isImplicitTokenAvailable = true
      lock.unlock()
      // Nothing lands in the pool when the implicit token comes back, so a
      // waiter has to be told about it explicitly.
      signalWakeup()
#if os(Windows)
    case .semaphore:
      _ = ReleaseSemaphore(semaphore, 1, nil)
#else
    case .byte(var byte):
      // Write back the byte that was read, not an arbitrary one.
      _ = retryOnInterrupt { write(writeFD, &byte, 1) }
#endif
    }
  }

  /// Unblocks any in-progress `acquire`, so that a finishing or cancelled build
  /// does not sit waiting for a token it no longer has any use for.
  func shutDown() {
    lock.lock()
    isShutDown = true
    lock.unlock()
    signalWakeup()
  }

  private var hasShutDown: Bool {
    lock.lock()
    defer { lock.unlock() }
    return isShutDown
  }

#if os(Windows)
  private func acquireFromPool() -> Token? {
    while true {
      // Recheck on every wake: a finished job may have returned the implicit
      // token, which adds nothing to the pool for us to take.
      if hasShutDown { return nil }
      if let token = takeImplicitToken() { return token }

      var handles: [HANDLE?] = [semaphore, wakeupEvent]
      let result = handles.withUnsafeMutableBufferPointer { buffer in
        WaitForMultipleObjects(DWORD(buffer.count), buffer.baseAddress, false,
                               DWORD(Self.pollIntervalMilliseconds))
      }
      if result == WAIT_OBJECT_0 {
        return Token(kind: .semaphore)
      }
      // Woken by `signalWakeup`, or timed out: loop and recheck.
      if result == WAIT_OBJECT_0 + 1 || result == WAIT_TIMEOUT {
        continue
      }
      return nil
    }
  }
#else
  private func acquireFromPool() -> Token? {
    while true {
      // Recheck on every wake: a finished job may have returned the implicit
      // token, which adds nothing to the pool for us to read.
      if hasShutDown { return nil }
      if let token = takeImplicitToken() { return token }

      let ready = waitForToken()
      if ready.wasWokenUp { drainWakeup() }
      guard ready.hasToken else { continue }

      var byte: UInt8 = 0
      let count = retryOnInterrupt { read(readFD, &byte, 1) }
      if count == 1 {
        return Token(kind: .byte(byte))
      }
      if count == 0 {
        // Every write end has been closed: the build is tearing down.
        return nil
      }
      // Another process took the byte we were woken for. On a FIFO the
      // descriptor is ours and non-blocking, so we loop and wait for the next
      // token. On an inherited pipe we cannot set `O_NONBLOCK` without changing
      // it for every other client, so the `read` above simply blocks -- correct
      // but not interruptible, which is why `JobServerDispatcher` bounds how
      // long it waits for this thread.
      guard errno == EAGAIN || errno == EWOULDBLOCK else { return nil }
    }
  }

  /// Waits until the pool has a token or the waiter is woken.
  private func waitForToken() -> (hasToken: Bool, wasWokenUp: Bool) {
    var descriptors = [
      pollfd(fd: readFD, events: Int16(POLLIN), revents: 0),
      pollfd(fd: wakeupReadFD, events: Int16(POLLIN), revents: 0),
    ]
    while true {
      let ready = poll(&descriptors, nfds_t(descriptors.count),
                       Self.pollIntervalMilliseconds)
      if ready < 0 && errno == EINTR { continue }
      guard ready > 0 else { return (false, false) }
      return (descriptors[0].revents != 0, descriptors[1].revents != 0)
    }
  }
#endif
}

/// Runs work on an `OperationQueue`, but only once a jobserver token is in
/// hand.
///
/// Tokens are taken on one dedicated thread rather than by enqueueing every
/// ready job and letting it block: a build can have hundreds of compilations
/// ready at once, and parking a thread apiece would cost more than the jobs.
final class JobServerDispatcher {
  private let jobServer: JobServer
  private let queue: OperationQueue

  /// Guards `pending`, `isShutDown` and `hasBrokerFinished`, and wakes the
  /// broker thread.
  private let condition = NSCondition()
  private var pending: [() -> Void] = []
  private var isShutDown = false
  private var hasBrokerFinished = false

  /// How long `shutDown` waits for the broker before giving up. The broker can
  /// be parked in an uninterruptible read, and hanging teardown is worse than
  /// leaking a token from a build that is ending anyway.
  private static let brokerShutDownTimeout: TimeInterval = 5

  init(jobServer: JobServer, queue: OperationQueue) {
    self.jobServer = jobServer
    self.queue = queue
  }

  func start() {
    let thread = Thread { [self] in brokerLoop() }
    thread.name = "org.swift.driver.jobserver"
    thread.start()
  }

  /// Schedules `body` to run once a token is available for it.
  func enqueue(_ body: @escaping () -> Void) {
    condition.lock()
    // Once the broker has stopped, nothing will ever drain `pending`, so run the
    // work directly rather than stranding it -- just as the broker's own
    // teardown does. Checked under the lock that sets the flag, so the two
    // cannot race.
    if hasBrokerFinished {
      condition.unlock()
      queue.addOperation(body)
      return
    }
    pending.append(body)
    condition.signal()
    condition.unlock()
  }

  /// Stops the broker and waits for the work it dispatched, so that every token
  /// is back in the pool before the driver exits.
  func shutDown() {
    condition.lock()
    isShutDown = true
    condition.broadcast()
    condition.unlock()

    // Wake the broker out of any wait on the pool itself.
    jobServer.shutDown()

    condition.lock()
    let deadline = Date(timeIntervalSinceNow: Self.brokerShutDownTimeout)
    while !hasBrokerFinished {
      guard condition.wait(until: deadline) else { break }
    }
    condition.unlock()

    queue.waitUntilAllOperationsAreFinished()
  }

  private func brokerLoop() {
    // However the loop exits -- shutdown, an unusable pool, or a path added
    // later -- this runs exactly once, so the broker can never leave without
    // draining its leftovers and marking itself finished.
    defer { dispatchRemainingWithoutTokens() }

    while true {
      condition.lock()
      while pending.isEmpty && !isShutDown {
        condition.wait()
      }
      let shouldStop = isShutDown
      condition.unlock()

      if shouldStop {
        return
      }

      // Take the token before claiming the work, so that we never hold a token
      // with nothing to spend it on. Only this thread removes from `pending`,
      // so it cannot have been emptied while we waited.
      guard let token = jobServer.acquire() else {
        return
      }

      condition.lock()
      let work = pending.isEmpty ? nil : pending.removeFirst()
      condition.unlock()

      guard let work = work else {
        jobServer.release(token)
        continue
      }

      queue.addOperation {
        defer { self.jobServer.release(token) }
        work()
      }
    }
  }

  /// The broker's teardown, invoked once from `brokerLoop`'s `defer` so it runs
  /// on every exit: runs whatever is left once the broker stops -- because the
  /// build is finishing or cancelled, or the pool became unusable. This work
  /// runs without tokens; taking tokens for it would only risk blocking
  /// teardown. The `assert` backstops the defer against a stray second caller.
  ///
  /// Everything happens under one lock hold, so the transitions are atomic:
  /// setting `hasBrokerFinished` alongside draining `pending` means an `enqueue`
  /// racing the exit either lands in this drain or sees the flag and dispatches
  /// itself -- it can never append to a `pending` no thread will read. Queueing
  /// before the broadcast means a `shutDown` woken by it already sees the work.
  private func dispatchRemainingWithoutTokens() {
    condition.lock()
    assert(!hasBrokerFinished, "the broker dispatches its leftovers exactly once, as it exits")
    hasBrokerFinished = true
    let remaining = pending
    pending.removeAll()
    remaining.forEach(queue.addOperation)
    condition.broadcast()
    condition.unlock()
  }
}

/// Reruns a system call that was interrupted by a signal.
private func retryOnInterrupt(_ body: () -> Int) -> Int {
  while true {
    let result = body()
    if result >= 0 || errno != EINTR {
      return result
    }
  }
}

private extension TSCBasic.Diagnostic.Message {
  static var warning_jobserver_unavailable: TSCBasic.Diagnostic.Message {
    .warning("jobserver unavailable: using '-j' instead. Add '+' to the parent make rule.")
  }
}
