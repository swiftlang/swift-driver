#!/usr/bin/env python

from __future__ import print_function

import argparse
from distutils import file_util
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
macos_deployment_target = '10.15'
macos_target_architectures = ['x86_64','arm64']

# Tools constructed as a part of the a development build toolchain
driver_toolchain_tools = ['swift', 'swift-frontend', 'clang', 'swift-help',
                          'swift-autolink-extract', 'lldb']

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

def swiftpm(action, swift_exec, swiftpm_args, env=None):
  cmd = [swift_exec, action] + swiftpm_args
  print(' '.join(cmd))
  subprocess.check_call(cmd, env=env)

def swiftpm_bin_path(swift_exec, swiftpm_args, env=None):
  swiftpm_args = list(filter(lambda arg: arg != '-v' and arg != '--verbose', swiftpm_args))
  cmd = [swift_exec, 'build', '--show-bin-path'] + swiftpm_args
  print(' '.join(cmd))
  return subprocess.check_output(cmd, env=env).strip()

def get_swiftpm_options(args):
  swiftpm_args = [
    '--package-path', args.package_path,
    '--build-path', args.build_path,
    '--configuration', args.configuration,
  ]

  if args.verbose:
    swiftpm_args += ['--verbose']

  if platform.system() == 'Darwin':
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

    if 'ANDROID_DATA' in os.environ:
      swiftpm_args += [
        '-Xlinker', '-rpath', '-Xlinker', '$ORIGIN/../lib/swift/android',
        # SwiftPM will otherwise try to compile against GNU strerror_r on
        # Android and fail.
        '-Xswiftc', '-Xcc', '-Xswiftc', '-U_GNU_SOURCE',
      ]
    else:
      # Library rpath for swift, dispatch, Foundation, etc. when installing
      swiftpm_args += [
        '-Xlinker', '-rpath', '-Xlinker', '$ORIGIN/../lib/swift/linux',
      ]

  return swiftpm_args

def install_binary(file, source_dir, install_dir, verbose):
  print('Installing %s into: %s' % (file, install_dir))
  cmd = ['rsync', '-a', os.path.join(source_dir.decode('UTF-8'), file), install_dir]
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
    print('install_name_tool command failed: ')
    print(stderr)
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
    print('install_name_tool command failed: ')
    print(stderr)
  if verbose:
    print(stdout)

def should_test_parallel():
  if platform.system() == 'Linux':
    distro = platform.linux_distribution()
    if distro[0] != 'Ubuntu':
      # Workaround hang in Process.run() that hasn't been tracked down yet.
      return False
  return True

def handle_invocation(toolchain_bin, args):
  swiftpm_args = get_swiftpm_options(args)

  swift_exec = os.path.join(toolchain_bin, 'swift')

  env = os.environ
  # Use local dependencies (i.e. checked out next to swift-driver).
  if not args.no_local_deps:
    env['SWIFTCI_USE_LOCAL_DEPS'] = "1"

  if args.ninja_bin:
    env['NINJA_BIN'] = args.ninja_bin

  if args.sysroot:
    env['SDKROOT'] = args.sysroot

  if args.action == 'build':
    swiftpm('build', swift_exec, swiftpm_args, env)
  elif args.action == 'clean':
    print('Cleaning ' + args.build_path)
    shutil.rmtree(args.build_path, ignore_errors=True)
  elif args.action == 'test':
    for tool in driver_toolchain_tools:
        tool_path = os.path.join(toolchain_bin, tool)
        if os.path.exists(tool_path):
            env['SWIFT_DRIVER_' + tool.upper().replace('-','_') + '_EXEC'] = '%s' % (tool_path)
    env['SWIFT_EXEC'] = '%sc' % (swift_exec)
    test_args = swiftpm_args
    if should_test_parallel():
      test_args += ['--parallel']
    swiftpm('test', swift_exec, test_args, env)
  elif args.action == 'install':
    if platform.system() == 'Darwin':
      distribution_build_dir = os.path.join(args.build_path, 'dist')
      build_for_distribution(args, toolchain_bin, distribution_build_dir)
      install(args, distribution_build_dir)
    else:
      bin_path = swiftpm_bin_path(swift_exec, swiftpm_args, env)
      swiftpm('build', swift_exec, swiftpm_args, env)
      non_darwin_install(bin_path, args.toolchain, args.verbose)
  else:
    assert False, 'unknown action \'{}\''.format(args.action)


# Installation flow for non-darwin platforms, only copies over swift-driver and swift-help
# TODO: Unify CMake-based installation flow used on Darwin with this
def non_darwin_install(swiftpm_bin_path, toolchain, verbose):
  toolchain_bin = os.path.join(toolchain, 'bin')
  for exe in ['swift-driver', 'swift-help']:
    install_binary(exe, swiftpm_bin_path, toolchain_bin, verbose)

def install(args, build_dir):
  # Construct and install universal swift-driver, swift-help executables
  # and libSwiftDriver, libSwiftOptions libraries
  toolchain_bin = os.path.join(args.toolchain, 'bin')
  toolchain_lib = os.path.join(args.toolchain, 'lib', 'swift', 'macosx')
  toolchain_include = os.path.join(args.toolchain, 'include', 'swift')
  universal_dir = os.path.join(build_dir, 'universal-apple-macos%s' % macos_deployment_target)
  bin_dir = os.path.join(universal_dir, 'bin')
  lib_dir = os.path.join(universal_dir, 'lib')
  mkdir_p(universal_dir)
  mkdir_p(bin_dir)
  mkdir_p(lib_dir)

  # swift-driver and swift-help
  install_executables(args, build_dir, bin_dir, toolchain_bin)

  # libSwiftDriver and libSwiftOptions
  install_libraries(args, build_dir, lib_dir, toolchain_lib)

  # Binary Swift Modules:
  # swift-driver: SwiftDriver.swiftmodule, SwiftOptions.swiftmodule
  # swift-argument-parser: ArgumentParser.swiftmodule
  # swift-tools-support-core: TSCUtility.swiftmodule, TSCLibc.swiftmodule, TSCBasic.swiftmodule
  install_binary_swift_modules(args, build_dir, toolchain_lib)

  # Modulemaps for C Modules:
  # llbuild, TSCclibc
  install_c_module_includes(args, build_dir, toolchain_include)

def install_executables(args, build_dir, universal_bin_dir, toolchain_bin_dir):
  for exe in ['swift-driver', 'swift-help']:
    # Fixup rpaths
    for arch in macos_target_architectures:
      exe_bin_path = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                                  'swift-driver', 'bin', exe)
      driver_lib_dir_path = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                                         'swift-driver', 'lib')
      tsc_lib_dir_path = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                                      'swift-tools-support-core', 'lib')
      delete_rpath(driver_lib_dir_path, exe_bin_path, args.verbose)
      delete_rpath(tsc_lib_dir_path, exe_bin_path, args.verbose)

      # Only swift-driver relies libllbuild
      if exe == 'swift-driver':
        llbuild_lib_dir_path = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                                          'llbuild', 'lib')
        delete_rpath(llbuild_lib_dir_path, exe_bin_path, args.verbose)

      # Point to the installed toolchain's lib
      add_rpath('@executable_path/../lib/swift/macosx', exe_bin_path, args.verbose)

    # Merge the multiple architecture binaries into a universal binary and install
    output_bin_path = os.path.join(universal_bin_dir, exe)
    lipo_cmd = ['lipo']
    # Inputs
    for arch in macos_target_architectures:
      input_bin_path = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                                    'swift-driver', 'bin', exe)
      lipo_cmd.append(input_bin_path)
    lipo_cmd.extend(['-create', '-output', output_bin_path])
    subprocess.check_call(lipo_cmd)
    install_binary(exe, universal_bin_dir, toolchain_bin_dir, args.verbose)

def install_libraries(args, build_dir, universal_lib_dir, toolchain_lib_dir):
  # Fixup the llbuild and swift-driver rpath for libSwiftDriver
  for arch in macos_target_architectures:
    lib_path = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                                   'swift-driver', 'lib', 'libSwiftDriver' + shared_lib_ext)
    driver_lib_dir_path = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                                       'swift-driver', 'lib')
    llbuild_lib_dir_path = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                                        'llbuild', 'lib')
    delete_rpath(driver_lib_dir_path, lib_path, args.verbose)
    delete_rpath(llbuild_lib_dir_path, lib_path, args.verbose)

  # Fixup the TSC rpath for libSwiftDriver and libSwiftOptions
  for lib in ['libSwiftDriver', 'libSwiftOptions']:
    for arch in macos_target_architectures:
      lib_path = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                              'swift-driver', 'lib', lib + shared_lib_ext)
      tsc_lib_dir_path = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                                      'swift-tools-support-core', 'lib')
      delete_rpath(tsc_lib_dir_path, lib_path, args.verbose)

  # Install the libSwiftDriver and libSwiftOptions shared libraries into the toolchain lib
  for lib in ['libSwiftDriver', 'libSwiftOptions']:
    shared_lib_file = lib + shared_lib_ext
    output_dylib_path = os.path.join(universal_lib_dir, shared_lib_file)
    lipo_cmd = ['lipo']
    for arch in macos_target_architectures:
      input_lib_path = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                                    'swift-driver', 'lib', shared_lib_file)
      lipo_cmd.append(input_lib_path)
    lipo_cmd.extend(['-create', '-output', output_dylib_path])
    subprocess.check_call(lipo_cmd)
    install_binary(shared_lib_file, universal_lib_dir, toolchain_lib_dir, args.verbose)

  for lib in ['libTSCBasic', 'libTSCLibc', 'libTSCUtility']:
    shared_lib_file = lib + shared_lib_ext
    output_dylib_path = os.path.join(universal_lib_dir, shared_lib_file)
    lipo_cmd = ['lipo']
    for arch in macos_target_architectures:
      input_lib_path = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                                    'swift-tools-support-core', 'lib', shared_lib_file)
      lipo_cmd.append(input_lib_path)
    lipo_cmd.extend(['-create', '-output', output_dylib_path])
    subprocess.check_call(lipo_cmd)
    install_binary(shared_lib_file, universal_lib_dir, toolchain_lib_dir, args.verbose)

def install_library(args, lib_name, ):
  shared_lib_file = lib + shared_lib_ext
  output_dylib_path = os.path.join(universal_lib_dir, shared_lib_file)
  lipo_cmd = ['lipo']
  for arch in macos_target_architectures:
    input_lib_path = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                                  'swift-driver', 'lib', shared_lib_file)
    lipo_cmd.append(input_lib_path)
  lipo_cmd.extend(['-create', '-output', output_dylib_path])
  subprocess.check_call(lipo_cmd)
  install_binary(shared_lib_file, universal_lib_dir, toolchain_lib_dir, args.verbose)

def install_binary_swift_modules(args, build_dir, toolchain_lib_dir):
  # The common subpath from a project's build directory to where its build products are found
  product_subpath = 'swift'

  # swift-driver
  for module in ['SwiftDriver', 'SwiftOptions']:
    install_module(args, build_dir, product_subpath, toolchain_lib_dir, module, 'swift-driver')

  # swift-argument-parser
  install_module(args, build_dir, product_subpath, toolchain_lib_dir, 'ArgumentParser', 'swift-argument-parser')

  # swift-tools-support-core
  for module in ['TSCUtility', 'TSCLibc', 'TSCBasic']:
    install_module(args, build_dir, product_subpath, toolchain_lib_dir, module, 'swift-tools-support-core')

  # llbuildSwift
  llbuild_product_subpath = os.path.join('products', 'llbuildSwift')
  install_module(args, build_dir, llbuild_product_subpath, toolchain_lib_dir, 'llbuildSwift', 'llbuild')

def install_c_module_includes(args, build_dir, toolchain_include_dir):
  # TSCclibc C module's modulemap and header files
  tscc_include_dir = os.path.join(os.path.dirname(args.package_path), 'swift-tools-support-core', 'Sources',
                                  'TSCclibc', 'include')
  install_module_includes(args, toolchain_include_dir, tscc_include_dir, 'TSCclibc')

  # llbuild C module's modulemap and header files
  llbuild_include_dir = os.path.join(os.path.dirname(args.package_path), 'llbuild', 'products',
                                     'libllbuild', 'include')
  install_module_includes(args, toolchain_include_dir, llbuild_include_dir, 'llbuild')

def install_module(args, build_dir, product_subpath, toolchain_lib, module_name, source_package):
  toolchain_module_dir = os.path.join(toolchain_lib, module_name + '.swiftmodule')
  mkdir_p(toolchain_module_dir)
  for arch in macos_target_architectures:
    swift_dir = os.path.join(build_dir, arch + '-apple-macos' + macos_deployment_target,
                             source_package, product_subpath)
    for fileext in ['.swiftmodule', '.swiftdoc']:
      install_binary(module_name + fileext, swift_dir, toolchain_module_dir, args.verbose)
      os.rename(os.path.join(toolchain_module_dir, module_name + fileext),
                os.path.join(toolchain_module_dir, arch + '-apple-macos' + fileext))

def install_module_includes(args, toolchain_include_dir, src_include_dir, dst_module_name):
  toolchain_module_include_dir = os.path.join(toolchain_include_dir, dst_module_name)
  if os.path.exists(toolchain_module_include_dir):
    shutil.rmtree(toolchain_module_include_dir, ignore_errors=True)
  shutil.copytree(src_include_dir, toolchain_module_include_dir)

def build_for_distribution(args, toolchain_bin, build_dir):
  print('Preparing SwiftDriver for distribution using CMake.')
  swiftc_exec = os.path.join(toolchain_bin, 'swiftc')

  # Targets for which we must build swift-driver to distribute
  if platform.system() == 'Darwin':
    targets = [x + '-apple-macos' + macos_deployment_target for x in macos_target_architectures]
  else:
    targets = [get_build_target(swiftc_path, args)]

  for target in targets:
    base_cmake_flags = [
      '-DCMAKE_Swift_FLAGS=-target %s' % target,
    ]
    if platform.system() == 'Darwin':
      base_cmake_flags.append('-DCMAKE_OSX_DEPLOYMENT_TARGET=%s' % macos_deployment_target)

    # Target directory to build distribution artifacts
    cmake_target_dir = os.path.join(build_dir, target)
    # LLBuild
    build_llbuild_using_cmake(args, target, swiftc_exec, cmake_target_dir, base_cmake_flags)
    # TSC
    build_tsc_using_cmake(args, target, swiftc_exec, cmake_target_dir, base_cmake_flags)
    # Argument Parser
    build_argument_parser_using_cmake(args, target, swiftc_exec, cmake_target_dir, base_cmake_flags)
    # Yams
    build_yams_using_cmake(args, target, swiftc_exec, cmake_target_dir, base_cmake_flags)
    # SwiftDriver
    build_swift_driver_using_cmake(args, target, swiftc_exec, cmake_target_dir, base_cmake_flags)

def build_llbuild_using_cmake(args, target, swiftc_exec, cmake_target_dir, base_cmake_flags):
  print('Building llbuild for target: %s' % target)
  llbuild_source_dir = os.path.join(os.path.dirname(args.package_path), 'llbuild')
  llbuild_build_dir = os.path.join(cmake_target_dir, 'llbuild')
  llbuild_api_dir = os.path.join(llbuild_build_dir, '.cmake/api/v1/query')
  mkdir_p(llbuild_api_dir)
  subprocess.check_call(['touch', os.path.join(llbuild_api_dir, 'codemodel-v2')])
  flags = [
        '-DCMAKE_C_COMPILER:=clang',
        '-DCMAKE_CXX_COMPILER:=clang++',
        '-DCMAKE_CXX_FLAGS=-target %s' % target,
        '-DLLBUILD_SUPPORT_BINDINGS:=Swift'
    ]
  if platform.system() == 'Darwin':
    flags.append('-DCMAKE_OSX_ARCHITECTURES=%s' % target.split('-')[0])
  llbuild_cmake_flags = base_cmake_flags + flags
  if args.sysroot:
    llbuild_cmake_flags.append('-DSQLite3_INCLUDE_DIR=%s/usr/include' % args.sysroot)
    # FIXME: This may be particularly hacky but CMake finds a different version of libsqlite3
    # on some machines. This is also Darwin-specific...
    llbuild_cmake_flags.append('-DSQLite3_LIBRARY=%s/usr/lib/libsqlite3.tbd' % args.sysroot)
  cmake_build(args, swiftc_exec, llbuild_cmake_flags, llbuild_source_dir, llbuild_build_dir)

def build_tsc_using_cmake(args, target, swiftc_exec, cmake_target_dir, base_cmake_flags):
  print('Building TSC for target: %s' % target)
  tsc_source_dir = os.path.join(os.path.dirname(args.package_path), 'swift-tools-support-core')
  tsc_build_dir = os.path.join(cmake_target_dir, 'swift-tools-support-core')
  cmake_build(args, swiftc_exec, base_cmake_flags, tsc_source_dir, tsc_build_dir)

def build_yams_using_cmake(args, target, swiftc_exec, cmake_target_dir, base_cmake_flags):
  print('Building Yams for target: %s' % target)
  yams_source_dir = os.path.join(os.path.dirname(args.package_path), 'yams')
  yams_build_dir = os.path.join(cmake_target_dir, 'yams')
  yams_flags = base_cmake_flags + ['-DBUILD_SHARED_LIBS=OFF', '-DCMAKE_C_FLAGS=-target %s' % target]
  cmake_build(args, swiftc_exec, yams_flags, yams_source_dir, yams_build_dir)

def build_argument_parser_using_cmake(args, target, swiftc_exec, cmake_target_dir, base_cmake_flags):
  print('Building Argument Parser for target: %s' % target)
  parser_source_dir = os.path.join(os.path.dirname(args.package_path), 'swift-argument-parser')
  parser_build_dir = os.path.join(cmake_target_dir, 'swift-argument-parser')
  custom_flags = ['-DBUILD_SHARED_LIBS=OFF', '-DBUILD_TESTING=NO', '-DBUILD_EXAMPLES=NO']
  parser_flags = base_cmake_flags + custom_flags
  cmake_build(args, swiftc_exec, parser_flags, parser_source_dir, parser_build_dir)
  return

def build_swift_driver_using_cmake(args, target, swiftc_exec, cmake_target_dir, base_cmake_flags):
  print('Building Swift Driver for target: %s' % target)
  driver_source_dir = args.package_path
  driver_build_dir = os.path.join(cmake_target_dir, 'swift-driver')
  # TODO: Enable Library Evolution
  swift_flags = ''
  flags = [
        '-DLLBuild_DIR=' + os.path.join(os.path.join(cmake_target_dir, 'llbuild'), 'cmake/modules'),
        '-DTSC_DIR=' + os.path.join(os.path.join(cmake_target_dir, 'swift-tools-support-core'), 'cmake/modules'),
        '-DYams_DIR=' + os.path.join(os.path.join(cmake_target_dir, 'yams'), 'cmake/modules'),
        '-DArgumentParser_DIR=' + os.path.join(os.path.join(cmake_target_dir, 'swift-argument-parser'), 'cmake/modules'),
        swift_flags
    ]
  driver_cmake_flags = base_cmake_flags + flags
  cmake_build(args, swiftc_exec, driver_cmake_flags, driver_source_dir, driver_build_dir)

def cmake_build(args, swiftc_exec, cmake_args, source_path, build_dir):
  """Configure with CMake and build with Ninja"""
  swift_flags = ''
  if args.sysroot:
    swift_flags = '-sdk %s' % args.sysroot
  cmd = [
    args.cmake_bin, '-G', 'Ninja',
    '-DCMAKE_MAKE_PROGRAM=%s' % args.ninja_bin,
    '-DCMAKE_BUILD_TYPE:=Release',
    '-DCMAKE_Swift_FLAGS=' + swift_flags,
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
    print(' '.join(ninja_cmd))
  ninjaProcess = subprocess.Popen(ninja_cmd, cwd=build_dir,
                                  stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE,
                                  env = os.environ)
  stdout, stderr = ninjaProcess.communicate()
  if ninjaProcess.returncode != 0:
    print(stdout)
    print('Ninja invocation failed: ')
    print(stderr)
    sys.exit(ninjaProcess.returncode)
  if args.verbose:
    print(stdout)

def get_build_target(swiftc_path, args):
    """Returns the target-triple of the current machine."""
    try:
        target_info_json = subprocess.check_output([swiftc_path, '-print-target-info'],
                                                   stderr=subprocess.PIPE,
                                                   universal_newlines=True).strip()
        args.target_info = json.loads(target_info_json)
        return args.target_info['target']['unversionedTriple']
    except Exception as e:
        error(str(e))

def main():
  parser = argparse.ArgumentParser(description='Build along with the Swift build-script.')
  def add_common_args(parser):
    parser.add_argument('--package-path', metavar='PATH', help='directory of the package to build', default='.')
    parser.add_argument('--toolchain', required=True, metavar='PATH', help='build using the toolchain at PATH')
    parser.add_argument('--ninja-bin', metavar='PATH', help='ninja binary to use for testing')
    parser.add_argument('--cmake-bin', metavar='PATH', help='cmake binary to use for building')
    parser.add_argument('--build-path', metavar='PATH', default='.build', help='build in the given path')
    parser.add_argument('--configuration', '-c', default='debug', help='build using configuration (release|debug)')
    parser.add_argument('--no-local-deps', action='store_true', help='use normal remote dependencies when building')
    parser.add_argument('--verbose', '-v', action='store_true', help='enable verbose output')

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

  if platform.system() == 'Darwin':
    args.sysroot = call_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], verbose=args.verbose)
  else:
    args.sysroot = None

  if args.toolchain:
    toolchain_bin = os.path.join(args.toolchain, 'bin')
  else:
    toolchain_bin = ''

  handle_invocation(toolchain_bin, args)

if __name__ == '__main__':
  main()
