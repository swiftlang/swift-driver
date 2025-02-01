//===--------------- DateAdditions.swift - Swift Date Additions -----------===//
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

#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Bionic)
import Bionic
#endif

/// Represents a time point value with nanosecond precision.
///
/// - Warning: The accuracy of measured `TimePoint` values is an OS-dependent property.
///            `TimePoint` does not correct for OS-level differences in e.g.
///             clock epochs. This makes it unsuitable for serialization in
///             products that are expected to transit between machines.
public struct TimePoint: Equatable, Comparable, Hashable {
  public var seconds: UInt64
  public var nanoseconds: UInt32

  public init(seconds: UInt64, nanoseconds: UInt32) {
    self.seconds = seconds
    self.nanoseconds = nanoseconds
  }

  public static func < (lhs: TimePoint, rhs: TimePoint) -> Bool {
    return (lhs.seconds, lhs.nanoseconds) < (rhs.seconds, rhs.nanoseconds)
  }
}

extension TimePoint {
  public static func seconds(_ value: Int64) -> TimePoint {
    precondition(value >= 0,
                 "Duration value in seconds is \(value), but cannot be negative")
    return TimePoint(seconds: UInt64(value), nanoseconds: 0)
  }

  public static func nanoseconds(_ value: Int) -> TimePoint {
    precondition(value >= 0,
                 "Duration value in nanoseconds is \(value), but cannot be negative")
    let (seconds, nanos) = value.quotientAndRemainder(dividingBy: TimePoint.nanosecondsPerSecond)
    return TimePoint(seconds: UInt64(seconds),
                     nanoseconds: UInt32(nanos))
  }
}

extension TimePoint: AdditiveArithmetic {
  public static var zero: TimePoint {
    return .seconds(0)
  }

  public static func + (lhs: TimePoint, rhs: TimePoint) -> TimePoint {
    // Add raw operands
    var seconds = lhs.seconds + rhs.seconds
    var nanos = lhs.nanoseconds + rhs.nanoseconds
    // Normalize nanoseconds
    if nanos >= TimePoint.nanosecondsPerSecond {
      nanos -= UInt32(TimePoint.nanosecondsPerSecond)
      seconds += 1
    }
    return TimePoint(seconds: seconds, nanoseconds: nanos)
  }

  public static func - (lhs: TimePoint, rhs: TimePoint) -> TimePoint {
    // Subtract raw operands
    var seconds = lhs.seconds - rhs.seconds
    // Normalize nanoseconds
    let nanos: UInt32
    if lhs.nanoseconds >= rhs.nanoseconds {
      nanos = lhs.nanoseconds - rhs.nanoseconds
    } else {
      // Subtract nanoseconds with carry - order of operations here
      // is important to avoid overflow.
      nanos = lhs.nanoseconds + UInt32(TimePoint.nanosecondsPerSecond) - rhs.nanoseconds
      seconds -= 1
    }
    return TimePoint(seconds: seconds, nanoseconds: nanos)
  }
}

extension TimePoint{
  public static func now() -> TimePoint {
    #if os(Windows)
    var ftTime: FILETIME = FILETIME()
    GetSystemTimePreciseAsFileTime(&ftTime)

    let result: UInt64 = (UInt64(ftTime.dwLowDateTime) << 0)
                       + (UInt64(ftTime.dwHighDateTime) << 32)
    // Windows ticks in 100 nanosecond intervals.
    return .seconds(Int64(result / 10_000_000))
    #else
    var tv = timeval()
    gettimeofday(&tv, nil)
    return TimePoint(seconds: UInt64(tv.tv_sec),
                     nanoseconds: UInt32(tv.tv_usec) * UInt32(Self.nanosecondsPerMicrosecond))
    #endif
  }

  public static var distantPast: TimePoint {
    return .zero
  }

  public static var distantFuture: TimePoint {
    // N.B. This is the seconds value of `Foundation.Date.distantFuture.timeIntervalSince1970`.
    // At time of writing, this is January 1, 4001 at 12:00:00 AM GMT, which is
    // far enough in the future that it's a reasonable time point for us to
    // compare against.
    //
    // However, it is important to note that Foundation's value cannot be both
    // fixed in time AND correct because of leap seconds and other calendrical
    // oddities.
    //
    // Other candidates include std::chrono's std::time_point::max - which is
    // about 9223372036854775807 - enough to comfortably bound the age of the
    // universe.
    return .seconds(64_092_211_200)
  }
}

extension TimePoint {
  fileprivate static let nanosecondsPerSecond: Int = 1_000_000_000
  fileprivate static let nanosecondsPerMillisecond: Int = 1_000_000
  fileprivate static let nanosecondsPerMicrosecond: Int = 1_000
  fileprivate static let millisecondsPerSecond: Int = 1_000
  fileprivate static let microsecondsPerSecond: Int = 1_000_000
}
