#ifndef DRIVER_DEFAULTS_CONSTANTS_H
#define DRIVER_DEFAULTS_CONSTANTS_H

/// Default Linker
///
/// This macro allows configuring the Swift driver build to specify a default
/// linker, overriding the existing heuristic.
///
/// NOTE: Darwin and Windows use clang as the linker. This does not affect the
///       linker that the clang linker selects.
#ifndef SWIFT_DEFAULT_LINKER
#define SWIFT_DEFAULT_LINKER
#endif
const char *defaultLinker;

#endif // DRIVER_DEFAULTS_CONSTANTS_H
