#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift open source project
##
## Copyright (c) 2025 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See http://swift.org/LICENSE.txt for license information
## See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

set -e

if command -v apt-get >/dev/null 2>&1 ; then # bookworm, noble, jammy
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y

    # Build dependencies
    apt-get install -y libsqlite3-dev libncurses-dev

    # Debug symbols
    apt-get install -y libc6-dbg
elif command -v dnf >/dev/null 2>&1 ; then # rhel-ubi9
    dnf update -y

    # Build dependencies
    dnf install -y sqlite-devel ncurses-devel

    # Debug symbols
    dnf debuginfo-install -y glibc
elif command -v yum >/dev/null 2>&1 ; then # amazonlinux2
    yum update -y

    # Build dependencies
    yum install -y sqlite-devel ncurses-devel

    # Debug symbols
    yum install -y yum-utils
    debuginfo-install -y glibc
fi
