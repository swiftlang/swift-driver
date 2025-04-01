#!/usr/bin/env python3

import argparse
import os
import json
import platform
import shutil
import subprocess
import sys
import errno

if platform.system() == 'Darwin':
    shared_lib_ext = '.dylib'
else:
    shared_lib_ext = '.so'
static_lib_ext = '.a'
macos_deployment_target = '10.15'

def error(message):
    print("--- %s: error: %s" % (os.path.basename(sys.argv[0]), message))
    sys.stdout.flush()
    raise SystemExit(1)

# Tools constructed as a part of the a development build toolchain
driver_toolchain_tools = ['swift', 'swift-frontend', 'clang', 'swift-help',
                          'swift-autolink-extract', 'lldb', 'swift-api-digester']

executables_to_install = ['swift-driver', 'swift-help', 'swift-build-sdk-interfaces']

def mkdir_p(path):
    """Create the given directory, if it does not exist."""
    try:
        os.makedirs(path)
    except OSError as e:
        # Ignore EEXIST, which may occur during a race condition.
        if e.errno != errno.EEXIST:
            raise

def call_output(cmd, cwd=None, stderr=False, verbose=False):
    """Calls a subprocess for its return data."""
    if verbose:
        print(' '.join(cmd))
    try:
        return subprocess.check_output(cmd, cwd=cwd, stderr=stderr, universal_newlines=True).strip()
    except Exception as e:
        if not verbose:
            print(' '.join(cmd))
        error(str(e))

def get_dispatch_cmake_arg(args):
    """Returns the CMake argument to the Dispatch configuration to use for building SwiftPM."""
    dispatch_dir = os.path.join(args.dispatch_build_dir, 'cmake/modules')
    return '-Ddispatch_DIR=' + dispatch_dir

def get_foundation_cmake_arg(args):
    """Returns the CMake argument to the Foundation configuration to use for building SwiftPM."""
    foundation_dir = os.path.join(args.foundation_build_dir, 'cmake/modules')
    return '-DFoundation_DIR=' + foundation_dir

def swiftpm(action, swift_exec, swiftpm_args, env=None):
  cmd = [swift_exec, action] + swiftpm_args
  print(' '.join(cmd))
  subprocess.check_call(cmd, env=env)

def swiftpm_bin_path(swift_exec, swiftpm_args, env=None):
  swiftpm_args = [arg for arg in swiftpm_args if arg != '-v' and arg != '--verbose']
  cmd = [swift_exec, 'build', '--show-bin-path'] + swiftpm_args
  print(' '.join(cmd))
  return subprocess.check_output(cmd, env=env, encoding='utf-8').strip()

def get_swiftpm_options(args):
  swiftpm_args = [
    '--package-path', args.package_path,
    '--scratch-path', args.build_path,
    '--configuration', args.configuration,
  ]

  if args.verbose:
    swiftpm_args += ['--verbose']

  build_os = args.build_target.split('-')[2]
  if build_os.startswith('macosx'):
    swiftpm_args += [
      # Relative library rpath for swift; will only be used when /usr/lib/swift
      # is not available.
      '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../lib/swift/macosx',
    ]
  else:
    swiftpm_args += [
      # Dispatch headers
      '-Xcxx', '-I', '-Xcxx',
      os.path.join(args.toolchain, 'lib', 'swift'),
      # For <Block.h>
      '-Xcxx', '-I', '-Xcxx',
      os.path.join(args.toolchain, 'lib', 'swift', 'Block'),
    ]

    if args.cross_compile_hosts:
      swiftpm_args += ['--destination', args.cross_compile_config]

    if args.action == 'install':
      swiftpm_args += ['--disable-local-rpath']

    if '-android' in args.build_target:
      swiftpm_args += [
        '-Xlinker', '-rpath', '-Xlinker', '$ORIGIN/../lib/swift/android',
      ]
    else:
      # Library rpath for swift, dispatch, Foundation, etc. when installing
      swiftpm_args += [
        '-Xlinker', '-rpath', '-Xlinker', '$ORIGIN/../lib/swift/' + build_os,
      ]

  if args.action == 'install':
    swiftpm_args += ['-Xswiftc', '-no-toolchain-stdlib-rpath']

  return swiftpm_args

def install_binary(file, source_dir, install_dir, verbose):
  print('Installing %s into: %s' % (file, install_dir))
  cmd = ['rsync', '-a', os.path.join(source_dir, file), install_dir]
  if verbose:
    print(' '.join(cmd))
  subprocess.check_call(cmd)

def delete_rpath(rpath, binary, verbose):
  cmd = ['install_name_tool', '-delete_rpath', rpath, binary]
  if verbose:
    print(' '.join(cmd))
  installToolProcess = subprocess.Popen(cmd,
                                        stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE)
  stdout, stderr = installToolProcess.communicate()
  if installToolProcess.returncode != 0:
    print('install_name_tool -delete_rpath command failed, assume incremental build and proceed.')
  if verbose:
    print(stdout)

def add_rpath(rpath, binary, verbose):
  cmd = ['install_name_tool', '-add_rpath', rpath, binary]
  if verbose:
    print(' '.join(cmd))
  installToolProcess = subprocess.Popen(cmd,
                                        stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE)
  stdout, stderr = installToolProcess.communicate()
  if installToolProcess.returncode != 0:
    print('install_name_tool -add_rpath command failed, assume incremental build and proceed.')
  if verbose:
    print(stdout)

def should_test_parallel():
  return False

def handle_invocation(args):
  swiftpm_args = get_swiftpm_options(args)
  toolchain_bin = os.path.join(args.toolchain, 'bin')
  swift_exec = os.path.join(toolchain_bin, 'swift')

  # Platform-specific targets for which we must build swift-driver
  if args.cross_compile_hosts:
    targets = args.cross_compile_hosts
  elif '-apple-macosx' in args.build_target:
    targets = [args.build_target + macos_deployment_target]
  else:
    targets = [args.build_target]

  env = os.environ
  # Use local dependencies (i.e. checked out next to swift-driver).
  if not args.no_local_deps:
    env['SWIFTCI_USE_LOCAL_DEPS'] = "1"

  if args.ninja_bin:
    env['NINJA_BIN'] = args.ninja_bin

  if args.sysroot:
    env['SDKROOT'] = args.sysroot

  env['SWIFT_EXEC'] = '%sc' % (swift_exec)

  if args.action == 'build':
    if args.cross_compile_hosts and not '-macosx' in args.cross_compile_hosts[0]:
      swiftpm('build', swift_exec, swiftpm_args, env)
    else:
      build_using_cmake(args, toolchain_bin, args.build_path, targets)

  elif args.action == 'clean':
    print('Cleaning ' + args.build_path)
    shutil.rmtree(args.build_path, ignore_errors=True)
  elif args.action == 'test':
    for tool in driver_toolchain_tools:
        tool_path = os.path.join(toolchain_bin, tool)
        if os.path.exists(tool_path):
            env['SWIFT_DRIVER_' + tool.upper().replace('-','_') + '_EXEC'] = '%s' % (tool_path)
    test_args = swiftpm_args
    test_args += ['-Xswiftc', '-enable-testing']
    if should_test_parallel():
      test_args += ['--parallel']
    # The test suite consults these variables to control what tests get run
    env['SWIFT_DRIVER_ENABLE_INTEGRATION_TESTS'] = "1"
    if args.lit_test_dir:
      env['SWIFT_DRIVER_LIT_DIR'] = args.lit_test_dir
    swiftpm('test', swift_exec, test_args, env)
  elif args.action == 'install':
    if '-apple-macosx' in args.build_target:
      build_using_cmake(args, toolchain_bin, args.build_path, targets)
      install(args, args.build_path, targets)
    else:
      bin_path = swiftpm_bin_path(swift_exec, swiftpm_args, env)
      swiftpm('build', swift_exec, swiftpm_args, env)
      non_darwin_install(args, bin_path)
  else:
    assert False, 'unknown action \'{}\''.format(args.action)

# Installation flow for non-darwin platforms, only copies over swift-driver and swift-help
# TODO: Unify CMake-based installation flow used on Darwin with this
def non_darwin_install(args, swiftpm_bin_path):
  for prefix in args.install_prefixes:
    prefix_bin = os.path.join(prefix, 'bin')
    for exe in executables_to_install:
      install_binary(exe, swiftpm_bin_path, prefix_bin, args.verbose)

def install(args, build_dir, targets):
  # Construct and install universal swift-driver, swift-help executables
  # and libSwiftDriver, libSwiftOptions libraries, along with their dependencies.
  for prefix in args.install_prefixes:
    install_swiftdriver(args, build_dir, prefix, targets)

def install_swiftdriver(args, build_dir, prefix, targets) :
  install_bin = os.path.join(prefix, 'bin')
  install_lib = os.path.join(prefix, 'lib', 'swift', 'macosx')
  install_include = os.path.join(prefix, 'include', 'swift')
  universal_dir = os.path.join(build_dir, 'universal-apple-macos%s' % macos_deployment_target)
  bin_dir = os.path.join(universal_dir, 'bin')
  lib_dir = os.path.join(universal_dir, 'lib')
  mkdir_p(universal_dir)
  mkdir_p(bin_dir)
  mkdir_p(lib_dir)

  # swift-driver and swift-help
  install_executables(args, build_dir, bin_dir, install_bin, targets)

  # libSwiftDriver and libSwiftDriverExecution and libSwiftOptions
  install_libraries(args, build_dir, lib_dir, install_lib, targets)

  # Binary Swift Modules:
  # swift-driver: SwiftDriver.swiftmodule, SwiftOptions.swiftmodule
  # swift-tools-support-core: TSCUtility.swiftmodule, TSCBasic.swiftmodule
  # swift-argument-parser: ArgumentParser.swiftmodule (disabled until needed)
  install_binary_swift_modules(args, build_dir, install_lib, targets)

  # Modulemaps for C Modules:
  # TSCclibc
  install_c_module_includes(args, build_dir, install_include)

# Install universal binaries for swift-driver and swift-help into the toolchain bin
# directory
def install_executables(args, build_dir, universal_bin_dir, toolchain_bin_dir, targets):
  for exe in executables_to_install:
    # Fixup rpaths
    for target in targets:
      exe_bin_path = os.path.join(build_dir, target,
                                  args.configuration, 'bin', exe)
      driver_lib_dir_path = os.path.join(build_dir, target,
                                         args.configuration, 'lib')
      delete_rpath(driver_lib_dir_path, exe_bin_path, args.verbose)

      for lib in ['swift-tools-support-core', 'swift-argument-parser']:
        lib_dir_path = os.path.join(build_dir, target,
                                    args.configuration, 'dependencies',
                                    lib, 'lib')
        delete_rpath(lib_dir_path, exe_bin_path, args.verbose)

      # Point to the installation toolchain's lib directory
      add_rpath('@executable_path/../lib/swift/macosx', exe_bin_path, args.verbose)

    # Merge the multiple architecture binaries into a universal binary and install
    output_bin_path = os.path.join(universal_bin_dir, exe)
    lipo_cmd = ['lipo']
    # Inputs
    for target in targets:
      input_bin_path = os.path.join(build_dir, target,
                                    args.configuration, 'bin', exe)
      lipo_cmd.append(input_bin_path)
    lipo_cmd.extend(['-create', '-output', output_bin_path])
    subprocess.check_call(lipo_cmd)
    install_binary(exe, universal_bin_dir, toolchain_bin_dir, args.verbose)

# Install shared libraries for the driver and its dependencies into the toolchain
def install_libraries(args, build_dir, universal_lib_dir, toolchain_lib_dir, targets):
  # Fixup the SwiftDriver rpath for libSwiftDriver and libSwiftDriverExecution
  for lib in ['libSwiftDriver', 'libSwiftDriverExecution']:
    for target in targets:
      lib_path = os.path.join(build_dir, target,
                                     args.configuration, 'lib', lib + shared_lib_ext)
      driver_lib_dir_path = os.path.join(build_dir, target,
                                         args.configuration, 'lib')
      delete_rpath(driver_lib_dir_path, lib_path, args.verbose)

  # Fixup the TSC and llbuild rpaths
  driver_libs = [os.path.join('lib', d) for d in ['libSwiftDriver', 'libSwiftOptions', 'libSwiftDriverExecution']]
  tsc_libs = [os.path.join('dependencies', 'swift-tools-support-core', 'lib', d) for d in ['libTSCBasic', 'libTSCUtility']]
  for lib in driver_libs + tsc_libs:
    for target in targets:
      lib_path = os.path.join(build_dir, target,
                              args.configuration, lib + shared_lib_ext)
      for dep in ['swift-tools-support-core', 'llbuild']:
        lib_dir_path = os.path.join(build_dir, target,
                                        args.configuration, 'dependencies',
                                        dep, 'lib')
        delete_rpath(lib_dir_path, lib_path, args.verbose)

  # Install the libSwiftDriver and libSwiftOptions and libSwiftDriverExecution
  # shared libraries into the toolchain lib
  package_subpath = args.configuration
  for lib in ['libSwiftDriver', 'libSwiftOptions', 'libSwiftDriverExecution']:
    install_library(args, build_dir, package_subpath, lib, shared_lib_ext,
                    universal_lib_dir, toolchain_lib_dir, 'swift-driver', targets)

  # Install the swift-tools-support core shared libraries into the toolchain lib
  package_subpath = os.path.join(args.configuration, 'dependencies', 'swift-tools-support-core')
  for lib in ['libTSCBasic', 'libTSCUtility']:
    install_library(args, build_dir, package_subpath, lib, shared_lib_ext,
                    universal_lib_dir, toolchain_lib_dir, 'swift-tools-support-core', targets)

  # Install the swift-argument-parser shared libraries into the toolchain lib
  package_subpath = os.path.join(args.configuration, 'dependencies', 'swift-argument-parser')
  for (lib, ext) in [('libArgumentParser', shared_lib_ext), ('libArgumentParserToolInfo', static_lib_ext)]:
      install_library(args, build_dir, package_subpath, lib, ext,
                      universal_lib_dir, toolchain_lib_dir,'swift-argument-parser', targets)

  # Install the llbuild core shared libraries into the toolchain lib
  package_subpath = os.path.join(args.configuration, 'dependencies', 'llbuild')
  for lib in ['libllbuildSwift']:
    install_library(args, build_dir, package_subpath, lib, shared_lib_ext,
                    universal_lib_dir, toolchain_lib_dir,'llbuild', targets)

# Create a universal shared-library file and install it into the toolchain lib
def install_library(args, build_dir, package_subpath, lib_name, lib_ext,
                    universal_lib_dir, toolchain_lib_dir, package_name, targets):
  lib_file = lib_name + lib_ext
  output_dylib_path = os.path.join(universal_lib_dir, lib_file)
  lipo_cmd = ['lipo']
  for target in targets:
    input_lib_path = os.path.join(build_dir, target,
                                  package_subpath, 'lib', lib_file)
    lipo_cmd.append(input_lib_path)
  lipo_cmd.extend(['-create', '-output', output_dylib_path])
  subprocess.check_call(lipo_cmd)
  install_binary(lib_file, universal_lib_dir, toolchain_lib_dir, args.verbose)

# Install binary .swiftmodule files for the driver and its dependencies into the toolchain lib
def install_binary_swift_modules(args, build_dir, toolchain_lib_dir, targets):
  # The common subpath from a project's build directory to where its build products are found
  product_subpath = 'swift'

  # swift-driver
  package_subpath = os.path.join(args.configuration, product_subpath)
  for module in ['SwiftDriver', 'SwiftOptions']:
    install_module(args, build_dir, package_subpath, toolchain_lib_dir, module, targets)

  # swift-tools-support-core
  package_subpath = os.path.join(args.configuration, 'dependencies', 'swift-tools-support-core',
                                 product_subpath)
  for module in ['TSCUtility', 'TSCBasic']:
    install_module(args, build_dir, package_subpath, toolchain_lib_dir, module, targets)

  # swift-argument-parser
  package_subpath = os.path.join(args.configuration, 'dependencies', 'swift-argument-parser',
                                 product_subpath)
  install_module(args, build_dir, package_subpath, toolchain_lib_dir, 'ArgumentParser', targets)


# Install the modulemaps and headers of the driver's C module dependencies into the toolchain
# include directory
def install_c_module_includes(args, build_dir, toolchain_include_dir):
  # TSCclibc C module's modulemap and header files
  tscc_include_dir = os.path.join(os.path.dirname(args.package_path), 'swift-tools-support-core', 'Sources',
                                  'TSCclibc', 'include')
  install_include_artifacts(args, toolchain_include_dir, tscc_include_dir, 'TSCclibc')

def install_module(args, build_dir, package_subpath, toolchain_lib, module_name, targets):
  toolchain_module_dir = os.path.join(toolchain_lib, module_name + '.swiftmodule')
  mkdir_p(toolchain_module_dir)
  for target in targets:
    swift_dir = os.path.join(build_dir, target,
                             package_subpath)
    for fileext in ['.swiftmodule', '.swiftdoc']:
      install_binary(module_name + fileext, swift_dir, toolchain_module_dir, args.verbose)
      os.rename(os.path.join(toolchain_module_dir, module_name + fileext),
                os.path.join(toolchain_module_dir, target + fileext))

# Copy over the contents of a module's include directory contents (modulemap, headers, etc.)
def install_include_artifacts(args, toolchain_include_dir, src_include_dir, dst_module_name):
  toolchain_module_include_dir = os.path.join(toolchain_include_dir, dst_module_name)
  if os.path.exists(toolchain_module_include_dir):
    shutil.rmtree(toolchain_module_include_dir, ignore_errors=True)
  shutil.copytree(src_include_dir, toolchain_module_include_dir)

def build_using_cmake(args, toolchain_bin, build_dir, targets):
  swiftc_exec = os.path.join(toolchain_bin, 'swiftc')
  base_swift_flags = []
  if args.configuration == 'debug':
    base_swift_flags.append('-Onone')
    base_swift_flags.append('-DDEBUG')

  if args.enable_asan:
    base_swift_flags.append('-sanitize=address')
    # This is currently needed to work around a swift-driver
    # bug when building with a 5.8 host toolchain.
    base_swift_flags.append('-Xclang-linker')
    base_swift_flags.append('-fsanitize=address')

  # Ensure we are not sharing the module cache with concurrent builds in CI
  base_swift_flags.append('-module-cache-path "{}"'.format(os.path.join(build_dir, 'module-cache')))

  for target in targets:
    base_cmake_flags = []
    swift_flags = base_swift_flags.copy()
    swift_flags.append('-target %s' % target)
    if '-apple-macosx' in args.build_target:
      base_cmake_flags.append('-DCMAKE_OSX_DEPLOYMENT_TARGET=%s' % macos_deployment_target)
      base_cmake_flags.append('-DCMAKE_OSX_ARCHITECTURES=%s' % target.split('-')[0])

    # Target directory for build artifacts
    # If building for a local compiler build, use the build directory directly
    if args.local_compiler_build:
      cmake_target_dir = build_dir
    else:
      cmake_target_dir = os.path.join(build_dir, target)

    driver_dir = os.path.join(cmake_target_dir, args.configuration)
    dependencies_dir = os.path.join(driver_dir, 'dependencies')

    # LLBuild
    build_llbuild_using_cmake(args, target, swiftc_exec, dependencies_dir,
                              base_cmake_flags, swift_flags)

    # TSC
    build_tsc_using_cmake(args, target, swiftc_exec, dependencies_dir,
                          base_cmake_flags, swift_flags)
    # Argument Parser
    build_argument_parser_using_cmake(args, target, swiftc_exec, dependencies_dir,
                                      base_cmake_flags, swift_flags)
    # SwiftDriver
    build_swift_driver_using_cmake(args, target, swiftc_exec, driver_dir,
                                   base_cmake_flags, swift_flags)

def build_llbuild_using_cmake(args, target, swiftc_exec, build_dir, base_cmake_flags, swift_flags):
  print('Building Swift Driver dependency: llbuild')
  llbuild_source_dir = os.path.join(os.path.dirname(args.package_path), 'llbuild')
  llbuild_build_dir = os.path.join(build_dir, 'llbuild')
  llbuild_api_dir = os.path.join(llbuild_build_dir, '.cmake/api/v1/query')
  mkdir_p(llbuild_api_dir)
  subprocess.check_call(['touch', os.path.join(llbuild_api_dir, 'codemodel-v2')])
  flags = [
        '-DCMAKE_C_COMPILER:=clang',
        '-DCMAKE_CXX_COMPILER:=clang++',
        '-DCMAKE_CXX_FLAGS=-target %s' % target,
        '-DLLBUILD_SUPPORT_BINDINGS:=Swift'
    ]
  llbuild_cmake_flags = base_cmake_flags + flags
  if args.sysroot:
    llbuild_cmake_flags.append('-DSQLite3_INCLUDE_DIR=%s/usr/include' % args.sysroot)
    # FIXME: This may be particularly hacky but CMake finds a different version of libsqlite3
    # on some machines. This is also Darwin-specific...
    if '-apple-macosx' in args.build_target:
      llbuild_cmake_flags.append('-DSQLite3_LIBRARY=%s/usr/lib/libsqlite3.tbd' % args.sysroot)
  llbuild_swift_flags = swift_flags[:]

  # Build only a subset of llbuild (in particular skipping tests)
  cmake_build(args, swiftc_exec, llbuild_cmake_flags, llbuild_swift_flags,
              llbuild_source_dir, llbuild_build_dir, 'products/all')

def build_tsc_using_cmake(args, target, swiftc_exec, build_dir, base_cmake_flags, swift_flags):
  print('Building Swift Driver dependency: TSC')
  tsc_source_dir = os.path.join(os.path.dirname(args.package_path), 'swift-tools-support-core')
  tsc_build_dir = os.path.join(build_dir, 'swift-tools-support-core')
  flags = []
  tsc_cmake_flags = base_cmake_flags + flags

  tsc_swift_flags = swift_flags[:]
  cmake_build(args, swiftc_exec, tsc_cmake_flags, tsc_swift_flags,
              tsc_source_dir, tsc_build_dir)

def build_argument_parser_using_cmake(args, target, swiftc_exec, build_dir, base_cmake_flags, swift_flags):
  print('Building Swift Driver dependency: Argument Parser')
  parser_source_dir = os.path.join(os.path.dirname(args.package_path), 'swift-argument-parser')
  parser_build_dir = os.path.join(build_dir, 'swift-argument-parser')
  custom_flags = ['-DBUILD_TESTING=NO', '-DBUILD_EXAMPLES=NO']
  parser_cmake_flags = base_cmake_flags + custom_flags
  parser_swift_flags = swift_flags[:]
  cmake_build(args, swiftc_exec, parser_cmake_flags, parser_swift_flags,
              parser_source_dir, parser_build_dir)
  return

def build_swift_driver_using_cmake(args, target, swiftc_exec, build_dir, base_cmake_flags, swift_flags):
  print('Building Swift Driver for target: %s' % target)
  driver_source_dir = args.package_path
  driver_build_dir = build_dir
  dependencies_dir = os.path.join(build_dir, 'dependencies')
  # TODO: Enable Library Evolution
  driver_swift_flags = swift_flags[:]
  flags = [
        '-DLLBuild_DIR=' + os.path.join(os.path.join(dependencies_dir, 'llbuild'), 'cmake/modules'),
        '-DTSC_DIR=' + os.path.join(os.path.join(dependencies_dir, 'swift-tools-support-core'), 'cmake/modules'),
        '-DArgumentParser_DIR=' + os.path.join(os.path.join(dependencies_dir, 'swift-argument-parser'), 'cmake/modules')]
  driver_cmake_flags = base_cmake_flags + flags
  cmake_build(args, swiftc_exec, driver_cmake_flags, driver_swift_flags,
              driver_source_dir, driver_build_dir)

def cmake_build(args, swiftc_exec, cmake_args, swift_flags, source_path,
                build_dir, ninja_target=None):
  """Configure with CMake and build with Ninja"""
  if args.sysroot:
    swift_flags.append('-sdk %s' % args.sysroot)
  cmd = [
    args.cmake_bin, '-G', 'Ninja',
    '-DCMAKE_MAKE_PROGRAM=%s' % args.ninja_bin,
    '-DCMAKE_BUILD_TYPE:=Release',
    '-DCMAKE_Swift_FLAGS=' + ' '.join(swift_flags),
    '-DCMAKE_Swift_COMPILER:=%s' % (swiftc_exec),
  ] + cmake_args + [source_path]
  if args.verbose:
    print(' '.join(cmd))
  mkdir_p(build_dir)
  subprocess.check_output(cmd, cwd=build_dir)

  # Invoke Ninja
  ninja_cmd = [args.ninja_bin]
  if args.verbose:
    ninja_cmd.append('-v')
  if ninja_target is not None:
    ninja_cmd.append(ninja_target)

  if args.verbose:
    print(' '.join(ninja_cmd))
  # Note: encoding is explicitly set to None to indicate that the output must
  # be bytes, not strings. This is to work around per-system differences in
  # default encoding. Some systems have a default encoding of 'ascii', but that
  # conflicts with this output, which can contain UTF encoded characters. The
  # bytes are then written, instead of printed, to bypass issues with encoding.
  ninjaProcess = subprocess.Popen(ninja_cmd, cwd=build_dir,
                                  stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE,
                                  env=os.environ,
                                  encoding=None)
  stdout, stderr = ninjaProcess.communicate()
  if ninjaProcess.returncode != 0:
    sys.stdout.buffer.write(stdout)
    print('Ninja invocation failed: ')
    sys.stderr.buffer.write(stderr)
    sys.exit(ninjaProcess.returncode)
  if args.verbose:
    sys.stdout.buffer.write(stdout)

def get_build_target(swiftc_path, args, cross_compile=False):
    """Returns the target-triple of the current machine."""
    try:
        command = [swiftc_path, '-print-target-info']
        if cross_compile:
            cross_compile_json = json.load(open(args.cross_compile_config))
            command += ['-target', cross_compile_json["target"]]
        target_info_json = subprocess.check_output(command,
                                                   stderr=subprocess.PIPE,
                                                   universal_newlines=True).strip()
        args.target_info = json.loads(target_info_json)
        triple = args.target_info['target']['triple']
        # Windows also wants unversionedTriple, but does not use this.
        if '-apple-macosx' in args.target_info["target"]["unversionedTriple"]:
          triple = args.target_info['target']['unversionedTriple']
        return triple
    except Exception as e:
        error(str(e))

def main():
  parser = argparse.ArgumentParser(description='Build along with the Swift build-script.')
  def add_common_args(parser):
    parser.add_argument('--package-path', metavar='PATH', help='directory of the package to build', default='.')
    parser.add_argument('--toolchain', required=True, metavar='PATH', help='build using the toolchain at PATH')
    parser.add_argument(
        '--prefix',
        dest='install_prefixes',
        nargs='*',
        help='paths (relative to the project root) where to install build products [%(default)s]',
        metavar='PATHS')
    parser.add_argument(
        '--cross-compile-hosts',
        dest='cross_compile_hosts',
        nargs='*',
        help='List of cross compile hosts targets.',
        default=[])
    parser.add_argument(
        '--cross-compile-config',
        metavar='PATH',
        help="A JSON SPM config file with Swift flags for cross-compilation")
    parser.add_argument('--ninja-bin', metavar='PATH', help='ninja binary to use for testing')
    parser.add_argument('--cmake-bin', metavar='PATH', help='cmake binary to use for building')
    parser.add_argument('--build-path', metavar='PATH', default='.build', help='build in the given path')
    parser.add_argument('--foundation-build-dir', metavar='PATH', help='Path to the Foundation build directory')
    parser.add_argument('--dispatch-build-dir', metavar='PATH', help='Path to the Dispatch build directory')
    parser.add_argument('--lit-test-dir', metavar='PATH', help='the test dir in the Swift build directory')
    parser.add_argument('--configuration', '-c', default='debug', help='build using configuration (release|debug)')
    parser.add_argument('--no-local-deps', action='store_true', help='use normal remote dependencies when building')
    parser.add_argument('--verbose', '-v', action='store_true', help='enable verbose output')
    parser.add_argument('--local_compiler_build', action='store_true', help='driver is being built for use with a local compiler build')
    parser.add_argument('--enable-asan', action='store_true', help='driver is being built with ASAN support')

  subparsers = parser.add_subparsers(title='subcommands', dest='action', metavar='action')
  clean_parser = subparsers.add_parser('clean', help='clean the package')
  add_common_args(clean_parser)

  build_parser = subparsers.add_parser('build', help='build the package')
  add_common_args(build_parser)

  test_parser = subparsers.add_parser('test', help='test the package')
  add_common_args(test_parser)

  install_parser = subparsers.add_parser('install', help='build the package')
  add_common_args(install_parser)

  args = parser.parse_args(sys.argv[1:])

  # Canonicalize paths
  args.package_path = os.path.abspath(args.package_path)
  args.build_path = os.path.abspath(args.build_path)
  args.toolchain = os.path.abspath(args.toolchain)

  swift_exec = os.path.join(os.path.join(args.toolchain, 'bin'), 'swiftc')
  args.build_target = get_build_target(swift_exec, args, cross_compile=(True if args.cross_compile_config else False))
  if '-apple-macosx' in args.build_target:
    args.sysroot = call_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], verbose=args.verbose)
  else:
    args.sysroot = None

  if (args.build_target == 'x86_64-apple-macosx' and 'macosx-arm64' in args.cross_compile_hosts):
      args.cross_compile_hosts = [args.build_target + macos_deployment_target, 'arm64-apple-macosx%s' % macos_deployment_target]
  elif (args.build_target == 'arm64-apple-macosx' and 'macosx-x86_64' in args.cross_compile_hosts):
      args.cross_compile_hosts = [args.build_target + macos_deployment_target, 'x86_64-apple-macosx%s' % macos_deployment_target]
  elif args.cross_compile_hosts and 'android-' in args.cross_compile_hosts[0]:
      print('Cross-compiling for %s' % args.cross_compile_hosts[0])
  elif args.cross_compile_hosts:
      error("cannot cross-compile for %s" % cross_compile_hosts)

  if args.cross_compile_hosts and args.local_compiler_build:
    error('Cross-compilation is currently not supported for the local compiler installation')

  if args.dispatch_build_dir:
    args.dispatch_build_dir = os.path.abspath(args.dispatch_build_dir)

  if args.foundation_build_dir:
    args.foundation_build_dir = os.path.abspath(args.foundation_build_dir)

  if args.lit_test_dir:
    args.lit_test_dir = os.path.abspath(args.lit_test_dir)

  # If a separate prefix has not been specified, installed into the specified toolchain
  if not args.install_prefixes:
    args.install_prefixes = [args.toolchain]

  handle_invocation(args)

if __name__ == '__main__':
  main()
