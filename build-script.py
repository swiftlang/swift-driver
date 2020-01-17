#!/usr/bin/env python

from __future__ import print_function

import argparse
import os
import subprocess
import sys
import tempfile
import errno
import platform

PACKAGE_DIR = os.path.dirname(os.path.realpath(__file__))
WORKSPACE_DIR = os.path.realpath(PACKAGE_DIR + '/..')

### Generate Xcode project

def xcode_gen(config):
    print('** Generate SwiftSyntax as an Xcode project **')
    os.chdir(PACKAGE_DIR)
    swiftpm_call = ['swift', 'package', 'generate-xcodeproj']
    if config:
        swiftpm_call.extend(['--xcconfig-overrides', config])
    check_call(swiftpm_call)

### Generic helper functions

def printerr(message):
    print(message, file=sys.stderr)

def note(message):
    print("--- %s: note: %s" % (os.path.basename(sys.argv[0]), message))
    sys.stdout.flush()

def fatal_error(message):
    printerr(message)
    sys.exit(1)

def escapeCmdArg(arg):
    if '"' in arg or ' ' in arg:
        return '"%s"' % arg.replace('"', '\\"')
    else:
        return arg


def call(cmd, env=os.environ, stdout=None, stderr=subprocess.STDOUT,
         verbose=False):
    if verbose:
        print(' '.join([escapeCmdArg(arg) for arg in cmd]))
    process = subprocess.Popen(cmd, env=env, stdout=stdout, stderr=stderr)
    process.wait()

    return process.returncode


def check_call(cmd, cwd=None, env=os.environ, verbose=False):
    if verbose:
        print(' '.join([escapeCmdArg(arg) for arg in cmd]))
    return subprocess.check_call(cmd, cwd=cwd, env=env, stderr=subprocess.STDOUT)


def realpath(path):
    if path is None:
        return None
    return os.path.realpath(path)


def get_swiftpm_invocation(toolchain, action, build_dir, multiroot_data_file,
                           release):
    swift_exec = os.path.join(toolchain, 'usr', 'bin', 'swift')

    swiftpm_call = [swift_exec, action]
    swiftpm_call.extend(['--package-path', PACKAGE_DIR])
    if platform.system() != 'Darwin':
      swiftpm_call.extend(['--enable-test-discovery'])
    if release:
        swiftpm_call.extend(['--configuration', 'release'])
    if build_dir:
        swiftpm_call.extend(['--build-path', build_dir])
    if multiroot_data_file:
        swiftpm_call.extend(['--multiroot-data-file', multiroot_data_file])

    return swiftpm_call

class Builder(object):
  def __init__(self, toolchain, build_dir, multiroot_data_file, release,
               verbose, disable_sandbox=False):
      self.swiftpm_call = get_swiftpm_invocation(toolchain=toolchain,
                                                 action='build',
                                                 build_dir=build_dir,
                                                 multiroot_data_file=multiroot_data_file,
                                                 release=release)
      if disable_sandbox:
          self.swiftpm_call.append('--disable-sandbox')
      if verbose:
          self.swiftpm_call.extend(['--verbose'])
      self.verbose = verbose

  def build(self, product_name):
      print('** Building ' + product_name + ' **')
      command = list(self.swiftpm_call)
      command.extend(['--product', product_name])

      env = dict(os.environ)
      env['SWIFT_BUILD_SCRIPT_ENVIRONMENT'] = '1'
      # Tell other projects in the unified build to use local dependencies
      env['SWIFTCI_USE_LOCAL_DEPS'] = '1'
      check_call(command, env=env, verbose=self.verbose)


## XCTest based tests

def run_xctests(toolchain, build_dir, multiroot_data_file, release, verbose):
    print('** Running XCTests **')
    swiftpm_call = get_swiftpm_invocation(toolchain=toolchain,
                                          action='test',
                                          build_dir=build_dir,
                                          multiroot_data_file=multiroot_data_file,
                                          release=release)

    if verbose:
        swiftpm_call.extend(['--verbose'])

    swiftpm_call.extend(['--test-product', 'SwiftDriverPackageTests'])

    env = dict(os.environ)
    env['SWIFT_BUILD_SCRIPT_ENVIRONMENT'] = '1'
    # Tell other projects in the unified build to use local dependencies
    env['SWIFTCI_USE_LOCAL_DEPS'] = '1'
    return call(swiftpm_call, env=env, verbose=verbose) == 0

def check_and_sync(file_path, install_path):
    cmd = ["rsync", "-a", file_path, install_path]
    note("installing %s: %s" % (os.path.basename(file_path), ' '.join(cmd)))
    result = subprocess.check_call(cmd)
    if result != 0:
        fatal_error("install failed with exit status %d" % (result,))

def install(build_dir, install_dir):
    check_and_sync(file_path=build_dir+'/swift-driver',
                   install_path=install_dir+'/'+'swift-driver')

### Main

def main():
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description='''
Build and test script for SwiftDriver.
''')

    basic_group = parser.add_argument_group('Basic')

    basic_group.add_argument('--build-dir', default=None, help='''
        The directory in which build products shall be put. If omitted a
        directory named '.build' will be put in the swift-driver directory.
        ''')
    basic_group.add_argument('-v', '--verbose', action='store_true', help='''
        Enable extensive logging of executed steps.
        ''')
    basic_group.add_argument('-r', '--release', action='store_true', help='''
      Build as a release build.
      ''')
    basic_group.add_argument('--install', action='store_true',
                             help='''
      Install the build artifact to a specified toolchain directory.
      ''')
    basic_group.add_argument('--generate-xcodeproj', action='store_true',
                             help='''
      Generate an Xcode project for SwiftDriver.
      ''')
    basic_group.add_argument('--xcconfig-path',
                             help='''
      The path to an xcconfig file for generating Xcode project.
      ''')
    basic_group.add_argument('--toolchain', help='''
      The path to the toolchain that shall be used to build SwiftDriver.
      ''')
    basic_group.add_argument('--install-dir',
                             help='''
      The directory to where the driver should be installed.
      ''')

    build_group = parser.add_argument_group('Build')
    build_group.add_argument('--disable-sandbox',
                             action='store_true',
                             help='Disable sandboxes when building with '
                                  'Swift PM')

    build_group.add_argument('--multiroot-data-file',
                             help='Path to an Xcode workspace to create a '
                                  'unified build of SwiftSyntax with other '
                                  'projects.')

    testing_group = parser.add_argument_group('Testing')
    testing_group.add_argument('-t', '--test', action='store_true',
                               help='Run tests')

    args = parser.parse_args(sys.argv[1:])

    if args.install:
        if not args.install_dir:
            fatal_error('Must specify directory to install')
        if not args.build_dir:
            fatal_error('Must specify build directory to copy from')
        if args.release:
            build_dir=args.build_dir + '/release'
        else:
            # will this ever happen?
            build_dir=args.build_dir + '/debug'
        install(build_dir=build_dir, install_dir=args.install_dir)
        sys.exit(0)

    if args.generate_xcodeproj:
        xcode_gen(config=args.xcconfig_path)
        sys.exit(0)

    try:
        builder = Builder(toolchain=args.toolchain,
                          build_dir=args.build_dir,
                          multiroot_data_file=args.multiroot_data_file,
                          release=args.release,
                          verbose=args.verbose,
                          disable_sandbox=args.disable_sandbox)
        builder.build('swift-driver')

    except subprocess.CalledProcessError as e:
        printerr('FAIL: Building SwiftSyntax failed')
        printerr('Executing: %s' % ' '.join(e.cmd))
        printerr(e.output)
        sys.exit(1)

    if args.test:
        try:
            success = run_tests(toolchain=args.toolchain,
                                build_dir=realpath(args.build_dir),
                                multiroot_data_file=args.multiroot_data_file,
                                release=args.release,
                                filecheck_exec=realpath(args.filecheck_exec),
                                verbose=args.verbose)
            if not success:
                # An error message has already been printed by the failing test
                # suite
                sys.exit(1)
            else:
                print('** All tests passed **')
        except subprocess.CalledProcessError as e:
            printerr('FAIL: Running tests failed')
            printerr('Executing: %s' % ' '.join(e.cmd))
            printerr(e.output)
            sys.exit(1)


if __name__ == '__main__':
    main()