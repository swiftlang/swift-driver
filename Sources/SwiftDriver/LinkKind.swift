/// Describes the kind of linker output we expect to produce.
public enum LinkOutputType {
  /// An executable file.
  case executable

  /// A shared library (e.g., .dylib or .so)
  case dynamicLibrary

  /// A static library (e.g., .a or .lib)
  case staticLibrary
};
