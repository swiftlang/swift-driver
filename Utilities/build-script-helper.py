#!/usr/bin/env python

from __future__ import print_function

import argparse
import os
import platform
import shutil
import subprocess
import sys

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

def install(swiftpm_bin_path, toolchain):
  toolchain_bin = os.path.join(toolchain, 'bin')
  for exe in ['swift-driver', 'swift-help']:
    install_binary(exe, swiftpm_bin_path, toolchain_bin, toolchain, is_executable=True)

def install_binary(file, source_dir, install_dir, toolchain, is_executable):
  cmd = ['rsync', '-a', os.path.join(source_dir.decode('UTF-8'), file), install_dir]
  print(' '.join(cmd))
  subprocess.check_call(cmd)

  if platform.system() == 'Darwin' and is_executable:
    result_path = os.path.join(install_dir, file)
    stdlib_rpath = os.path.join(toolchain, 'lib', 'swift', 'macosx')
    delete_rpath(stdlib_rpath, result_path)

def delete_rpath(rpath, binary):
  cmd = ["install_name_tool", "-delete_rpath", rpath, binary]
  print(' '.join(cmd))
  subprocess.check_call(cmd)


def should_test_parallel():
  if platform.system() == 'Linux':
    distro = platform.linux_distribution()
    if distro[0] != 'Ubuntu':
      # Workaround hang in Process.run() that hasn't been tracked down yet.
      return False
  return True


def handle_invocation(swift_exec, args):
  swiftpm_args = get_swiftpm_options(args)

  env = os.environ
  # Use local dependencies (i.e. checked out next to swift-driver).
  if not args.no_local_deps:
    env['SWIFTCI_USE_LOCAL_DEPS'] = "1"

  if args.ninja_bin:
    env['NINJA_BIN'] = args.ninja_bin

  print('Cleaning ' + args.build_path)
  shutil.rmtree(args.build_path, ignore_errors=True)

  if args.action == 'build':
    swiftpm('build', swift_exec, swiftpm_args, env)
  elif args.action == 'test':
    env['SWIFT_DRIVER_SWIFT_EXEC'] = '%sc' % (swift_exec)
    test_args = swiftpm_args
    if should_test_parallel():
      test_args += ['--parallel']
    swiftpm('test', swift_exec, test_args, env)
  elif args.action == 'install':
    bin_path = swiftpm_bin_path(swift_exec, swiftpm_args, env)
    swiftpm('build', swift_exec, swiftpm_args, env)
    install(bin_path, args.toolchain)
  else:
    assert False, 'unknown action \'{}\''.format(args.action)


def main():
  parser = argparse.ArgumentParser(description='Build along with the Swift build-script.')
  def add_common_args(parser):
    parser.add_argument('--package-path', metavar='PATH', help='directory of the package to build', default='.')
    parser.add_argument('--toolchain', required=True, metavar='PATH', help='build using the toolchain at PATH')
    parser.add_argument('--ninja-bin', metavar='PATH', help='ninja binary to use for testing')
    parser.add_argument('--build-path', metavar='PATH', default='.build', help='build in the given path')
    parser.add_argument('--configuration', '-c', default='debug', help='build using configuration (release|debug)')
    parser.add_argument('--no-local-deps', action='store_true', help='use normal remote dependencies when building')
    parser.add_argument('--verbose', '-v', action='store_true', help='enable verbose output')

  subparsers = parser.add_subparsers(title='subcommands', dest='action', metavar='action')
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

  if args.toolchain:
    swift_exec = os.path.join(args.toolchain, 'bin', 'swift')
  else:
    swift_exec = 'swift'

  handle_invocation(swift_exec, args)

if __name__ == '__main__':
  main()
