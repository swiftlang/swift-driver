//===--------------- TripleTests.swift - Swift Target Triple Tests --------===//
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
import XCTest

@_spi(Testing) import SwiftDriver
import class TSCBasic.DiagnosticsEngine

final class TripleTests: XCTestCase {
  func testBasics() throws {
    XCTAssertEqual(Triple("").arch, nil)
    XCTAssertEqual(Triple("kalimba").arch, .kalimba)
    XCTAssertEqual(Triple("m68k-unknown-linux-gnu").arch, .m68k)
    XCTAssertEqual(Triple("x86_64-apple-macosx").arch, .x86_64)
    XCTAssertEqual(Triple("blah-apple").arch, nil)
    XCTAssertEqual(Triple("x86_64-apple-macosx").vendor, .apple)
    XCTAssertEqual(Triple("x86_64-apple-macosx").os, .macosx)
    XCTAssertEqual(Triple("x86_64-apple-macosx-macabi").environment, .macabi)
    XCTAssertEqual(Triple("x86_64-apple-macosx-macabixxmacho").objectFormat, .macho)
    XCTAssertEqual(Triple("mipsn32").environment, .gnuabin32)

    XCTAssertEqual(Triple("x86_64-unknown-mylinux").osName, "mylinux")
    XCTAssertEqual(Triple("x86_64-unknown-mylinux-abi").osName, "mylinux")
    XCTAssertEqual(Triple("x86_64-unknown").osName, "")

    XCTAssertEqual(Triple("x86_64-apple-macosx10.13").osVersion, "10.13.0")
    XCTAssertEqual(Triple("x86_64-apple-macosx1x.13").osVersion, "0.13.0")
    XCTAssertEqual(Triple("x86_64-apple-macosx10.13.5-abi").osVersion, "10.13.5")

    XCTAssertEqual(Triple("arm64-unknown-none").arch, .aarch64)
    XCTAssertEqual(Triple("arm64-unknown-none").vendor, nil)
    XCTAssertEqual(Triple("arm64-unknown-none").os, .noneOS)
    XCTAssertEqual(Triple("arm64-unknown-none").environment, nil)
    XCTAssertEqual(Triple("arm64-unknown-none").objectFormat, .elf)

    XCTAssertEqual(Triple("xtensa-unknown-none").objectFormat, .elf)

    XCTAssertEqual(Triple("arm64-apple-none-macho").arch, .aarch64)
    XCTAssertEqual(Triple("arm64-apple-none-macho").vendor, .apple)
    XCTAssertEqual(Triple("arm64-apple-none-macho").os, .noneOS)
    XCTAssertEqual(Triple("arm64-apple-none-macho").environment, nil)
    XCTAssertEqual(Triple("arm64-apple-none-macho").objectFormat, .macho)

    XCTAssertEqual(Triple("x86_64-unknown-freebsd14.1").arch, .x86_64)
    XCTAssertEqual(Triple("x86_64-unknown-freebsd14.1").vendor, nil)
    XCTAssertEqual(Triple("x86_64-unknown-freebsd14.1").os, .freeBSD)
    XCTAssertEqual(Triple("x86_64-unknown-freebsd14.1").osNameUnversioned, "freebsd")
    XCTAssertEqual(Triple("x86_64-unknown-freebsd14.1").objectFormat, .elf)
  }

  func testBasicParsing() {
    var T: Triple

    T = Triple("")
    XCTAssertEqual(T.archName, "")
    XCTAssertEqual(T.vendorName, "")
    XCTAssertEqual(T.osName, "")
    XCTAssertEqual(T.environmentName, "")

    T = Triple("-")
    XCTAssertEqual(T.archName, "")
    XCTAssertEqual(T.vendorName, "")
    XCTAssertEqual(T.osName, "")
    XCTAssertEqual(T.environmentName, "")

    T = Triple("--")
    XCTAssertEqual(T.archName, "")
    XCTAssertEqual(T.vendorName, "")
    XCTAssertEqual(T.osName, "")
    XCTAssertEqual(T.environmentName, "")

    T = Triple("---")
    XCTAssertEqual(T.archName, "")
    XCTAssertEqual(T.vendorName, "")
    XCTAssertEqual(T.osName, "")
    XCTAssertEqual(T.environmentName, "")

    T = Triple("----")
    XCTAssertEqual(T.archName, "")
    XCTAssertEqual(T.vendorName, "")
    XCTAssertEqual(T.osName, "")
    XCTAssertEqual(T.environmentName, "-")

    T = Triple("a")
    XCTAssertEqual(T.archName, "a")
    XCTAssertEqual(T.vendorName, "")
    XCTAssertEqual(T.osName, "")
    XCTAssertEqual(T.environmentName, "")

    T = Triple("a-b")
    XCTAssertEqual(T.archName, "a")
    XCTAssertEqual(T.vendorName, "b")
    XCTAssertEqual(T.osName, "")
    XCTAssertEqual(T.environmentName, "")

    T = Triple("a-b-c")
    XCTAssertEqual(T.archName, "a")
    XCTAssertEqual(T.vendorName, "b")
    XCTAssertEqual(T.osName, "c")
    XCTAssertEqual(T.environmentName, "")

    T = Triple("a-b-c-d")
    XCTAssertEqual(T.archName, "a")
    XCTAssertEqual(T.vendorName, "b")
    XCTAssertEqual(T.osName, "c")
    XCTAssertEqual(T.environmentName, "d")
  }

  func testParsedIDs() {
    var T: Triple

    T = Triple("i386-apple-darwin")
    XCTAssertEqual(T.arch, Triple.Arch.x86)
    XCTAssertEqual(T.vendor, Triple.Vendor.apple)
    XCTAssertEqual(T.os, Triple.OS.darwin)
    XCTAssertEqual(T.environment, nil)

    T = Triple("i386-pc-elfiamcu")
    XCTAssertEqual(T.arch, Triple.Arch.x86)
    XCTAssertEqual(T.vendor, Triple.Vendor.pc)
    XCTAssertEqual(T.os, Triple.OS.elfiamcu)
    XCTAssertEqual(T.environment, nil)

    T = Triple("i386-pc-contiki-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.x86)
    XCTAssertEqual(T.vendor, Triple.Vendor.pc)
    XCTAssertEqual(T.os, Triple.OS.contiki)
    XCTAssertEqual(T.environment, nil)

    T = Triple("i386-pc-hurd-gnu")
    XCTAssertEqual(T.arch, Triple.Arch.x86)
    XCTAssertEqual(T.vendor, Triple.Vendor.pc)
    XCTAssertEqual(T.os, Triple.OS.hurd)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)

    T = Triple("x86_64-pc-linux-gnu")
    XCTAssertEqual(T.arch, Triple.Arch.x86_64)
    XCTAssertEqual(T.vendor, Triple.Vendor.pc)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)

    T = Triple("x86_64-pc-linux-musl")
    XCTAssertEqual(T.arch, Triple.Arch.x86_64)
    XCTAssertEqual(T.vendor, Triple.Vendor.pc)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.musl)

    T = Triple("powerpc-bgp-linux")
    XCTAssertEqual(T.arch, Triple.Arch.ppc)
    XCTAssertEqual(T.vendor, Triple.Vendor.bgp)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, nil)

    T = Triple("powerpc-bgp-cnk")
    XCTAssertEqual(T.arch, Triple.Arch.ppc)
    XCTAssertEqual(T.vendor, Triple.Vendor.bgp)
    XCTAssertEqual(T.os, Triple.OS.cnk)
    XCTAssertEqual(T.environment, nil)

    T = Triple("ppc-bgp-linux")
    XCTAssertEqual(T.arch, Triple.Arch.ppc)
    XCTAssertEqual(T.vendor, Triple.Vendor.bgp)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, nil)

    T = Triple("ppc32-bgp-linux")
    XCTAssertEqual(T.arch, Triple.Arch.ppc)
    XCTAssertEqual(T.vendor, Triple.Vendor.bgp)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, nil)

    T = Triple("powerpc64-bgq-linux")
    XCTAssertEqual(T.arch, Triple.Arch.ppc64)
    XCTAssertEqual(T.vendor, Triple.Vendor.bgq)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, nil)

    T = Triple("ppc64-bgq-linux")
    XCTAssertEqual(T.arch, Triple.Arch.ppc64)
    XCTAssertEqual(T.vendor, Triple.Vendor.bgq)
    XCTAssertEqual(T.os, Triple.OS.linux)

    T = Triple("powerpc-ibm-aix")
    XCTAssertEqual(T.arch, Triple.Arch.ppc)
    XCTAssertEqual(T.vendor, Triple.Vendor.ibm)
    XCTAssertEqual(T.os, Triple.OS.aix)
    XCTAssertEqual(T.environment, nil)

    T = Triple("powerpc64-ibm-aix")
    XCTAssertEqual(T.arch, Triple.Arch.ppc64)
    XCTAssertEqual(T.vendor, Triple.Vendor.ibm)
    XCTAssertEqual(T.os, Triple.OS.aix)
    XCTAssertEqual(T.environment, nil)

    T = Triple("powerpc-dunno-notsure")
    XCTAssertEqual(T.arch, Triple.Arch.ppc)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)
    XCTAssertEqual(T.environment, nil)

    T = Triple("arm-none-none-eabi")
    XCTAssertEqual(T.arch, Triple.Arch.arm)
    XCTAssertEqual(T.subArch, nil)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, .noneOS)
    XCTAssertEqual(T.environment, Triple.Environment.eabi)

    T = Triple("arm-none-unknown-eabi")
    XCTAssertEqual(T.arch, Triple.Arch.arm)
    XCTAssertEqual(T.subArch, nil)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)
    XCTAssertEqual(T.environment, Triple.Environment.eabi)

    T = Triple("arm-none-linux-musleabi")
    XCTAssertEqual(T.arch, Triple.Arch.arm)
    XCTAssertEqual(T.subArch, nil)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.musleabi)

    T = Triple("armv6hl-none-linux-gnueabi")
    XCTAssertEqual(T.arch, Triple.Arch.arm)
    XCTAssertEqual(T.subArch, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnueabi)

    T = Triple("armv7hl-none-linux-gnueabi")
    XCTAssertEqual(T.arch, Triple.Arch.arm)
    XCTAssertEqual(T.subArch, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnueabi)

    T = Triple("armv7em-apple-none-macho")
    XCTAssertEqual(T.arch, Triple.Arch.arm)
    XCTAssertEqual(T.subArch, Triple.SubArch.arm(.v7em))
    XCTAssertEqual(T.vendor, .apple)
    XCTAssertEqual(T.os, Triple.OS.noneOS)
    XCTAssertEqual(T.environment, nil)
    XCTAssertEqual(T.objectFormat, Triple.ObjectFormat.macho)

    T = Triple("amdil-unknown-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.amdil)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)

    T = Triple("amdil64-unknown-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.amdil64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)

    T = Triple("hsail-unknown-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.hsail)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)

    T = Triple("hsail64-unknown-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.hsail64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)

    T = Triple("m68k-unknown-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.m68k)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)

    T = Triple("sparcel-unknown-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.sparcel)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)

    T = Triple("spir-unknown-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.spir)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)

    T = Triple("spir64-unknown-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.spir64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)

    T = Triple("x86_64-unknown-ananas")
    XCTAssertEqual(T.arch, Triple.Arch.x86_64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.ananas)
    XCTAssertEqual(T.environment, nil)

    T = Triple("x86_64-unknown-cloudabi")
    XCTAssertEqual(T.arch, Triple.Arch.x86_64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.cloudABI)
    XCTAssertEqual(T.environment, nil)

    T = Triple("x86_64-unknown-fuchsia")
    XCTAssertEqual(T.arch, Triple.Arch.x86_64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.fuchsia)
    XCTAssertEqual(T.environment, nil)

    T = Triple("x86_64-unknown-hermit")
    XCTAssertEqual(T.arch, Triple.Arch.x86_64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.hermitcore)
    XCTAssertEqual(T.environment, nil)

    T = Triple("wasm32-unknown-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.wasm32)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)
    XCTAssertEqual(T.environment, nil)

    T = Triple("wasm32-unknown-wasi")
    XCTAssertEqual(T.arch, Triple.Arch.wasm32)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.wasi)
    XCTAssertEqual(T.environment, nil)

    T = Triple("wasm64-unknown-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.wasm64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)
    XCTAssertEqual(T.environment, nil)

    T = Triple("wasm64-unknown-wasi")
    XCTAssertEqual(T.arch, Triple.Arch.wasm64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.wasi)
    XCTAssertEqual(T.environment, nil)

    T = Triple("avr-unknown-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.avr)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)
    XCTAssertEqual(T.environment, nil)

    T = Triple("avr")
    XCTAssertEqual(T.arch, Triple.Arch.avr)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)
    XCTAssertEqual(T.environment, nil)

    T = Triple("lanai-unknown-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.lanai)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)
    XCTAssertEqual(T.environment, nil)

    T = Triple("lanai")
    XCTAssertEqual(T.arch, Triple.Arch.lanai)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)
    XCTAssertEqual(T.environment, nil)

    T = Triple("amdgcn-mesa-mesa3d")
    XCTAssertEqual(T.arch, Triple.Arch.amdgcn)
    XCTAssertEqual(T.vendor, Triple.Vendor.mesa)
    XCTAssertEqual(T.os, Triple.OS.mesa3d)
    XCTAssertEqual(T.environment, nil)

    T = Triple("amdgcn-amd-amdhsa")
    XCTAssertEqual(T.arch, Triple.Arch.amdgcn)
    XCTAssertEqual(T.vendor, Triple.Vendor.amd)
    XCTAssertEqual(T.os, Triple.OS.amdhsa)
    XCTAssertEqual(T.environment, nil)

    T = Triple("amdgcn-amd-amdpal")
    XCTAssertEqual(T.arch, Triple.Arch.amdgcn)
    XCTAssertEqual(T.vendor, Triple.Vendor.amd)
    XCTAssertEqual(T.os, Triple.OS.amdpal)
    XCTAssertEqual(T.environment, nil)

    T = Triple("riscv32-unknown-unknown")
    XCTAssertEqual(T.arch, Triple.Arch.riscv32)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, nil)
    XCTAssertEqual(T.environment, nil)

    T = Triple("riscv64-unknown-linux")
    XCTAssertEqual(T.arch, Triple.Arch.riscv64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, nil)

    T = Triple("riscv64-unknown-freebsd")
    XCTAssertEqual(T.arch, Triple.Arch.riscv64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.freeBSD)
    XCTAssertEqual(T.environment, nil)

    T = Triple("armv7hl-suse-linux-gnueabi")
    XCTAssertEqual(T.arch, Triple.Arch.arm)
    XCTAssertEqual(T.vendor, Triple.Vendor.suse)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnueabi)

    T = Triple("i586-pc-haiku")
    XCTAssertEqual(T.arch, Triple.Arch.x86)
    XCTAssertEqual(T.vendor, Triple.Vendor.pc)
    XCTAssertEqual(T.os, Triple.OS.haiku)
    XCTAssertEqual(T.environment, nil)

    T = Triple("x86_64-unknown-haiku")
    XCTAssertEqual(T.arch, Triple.Arch.x86_64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.haiku)
    XCTAssertEqual(T.environment, nil)

    T = Triple("m68k-suse-linux-gnu")
    XCTAssertEqual(T.arch, Triple.Arch.m68k)
    XCTAssertEqual(T.vendor, Triple.Vendor.suse)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)

    T = Triple("mips-mti-linux-gnu")
    XCTAssertEqual(T.arch, Triple.Arch.mips)
    XCTAssertEqual(T.vendor, Triple.Vendor.mipsTechnologies)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)

    T = Triple("mipsel-img-linux-gnu")
    XCTAssertEqual(T.arch, Triple.Arch.mipsel)
    XCTAssertEqual(T.vendor, Triple.Vendor.imaginationTechnologies)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)

    T = Triple("mips64-mti-linux-gnu")
    XCTAssertEqual(T.arch, Triple.Arch.mips64)
    XCTAssertEqual(T.vendor, Triple.Vendor.mipsTechnologies)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)

    T = Triple("mips64el-img-linux-gnu")
    XCTAssertEqual(T.arch, Triple.Arch.mips64el)
    XCTAssertEqual(T.vendor, Triple.Vendor.imaginationTechnologies)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)

    T = Triple("mips64el-img-linux-gnuabin32")
    XCTAssertEqual(T.arch, Triple.Arch.mips64el)
    XCTAssertEqual(T.vendor, Triple.Vendor.imaginationTechnologies)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabin32)

    T = Triple("mips64el-unknown-linux-gnuabi64")
    XCTAssertEqual(T.arch, Triple.Arch.mips64el)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabi64)
    XCTAssertEqual(T.subArch, nil)
    T = Triple("mips64el")
    XCTAssertEqual(T.arch, Triple.Arch.mips64el)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabi64)
    XCTAssertEqual(T.subArch, nil)

    T = Triple("mips64-unknown-linux-gnuabi64")
    XCTAssertEqual(T.arch, Triple.Arch.mips64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabi64)
    XCTAssertEqual(T.subArch, nil)
    T = Triple("mips64")
    XCTAssertEqual(T.arch, Triple.Arch.mips64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabi64)
    XCTAssertEqual(T.subArch, nil)

    T = Triple("mipsisa64r6el-unknown-linux-gnuabi64")
    XCTAssertEqual(T.arch, Triple.Arch.mips64el)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabi64)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))
    T = Triple("mips64r6el")
    XCTAssertEqual(T.arch, Triple.Arch.mips64el)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabi64)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))
    T = Triple("mipsisa64r6el")
    XCTAssertEqual(T.arch, Triple.Arch.mips64el)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabi64)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))

    T = Triple("mipsisa64r6-unknown-linux-gnuabi64")
    XCTAssertEqual(T.arch, Triple.Arch.mips64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabi64)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))
    T = Triple("mips64r6")
    XCTAssertEqual(T.arch, Triple.Arch.mips64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabi64)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))
    T = Triple("mipsisa64r6")
    XCTAssertEqual(T.arch, Triple.Arch.mips64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabi64)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))

    T = Triple("mips64el-unknown-linux-gnuabin32")
    XCTAssertEqual(T.arch, Triple.Arch.mips64el)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabin32)
    XCTAssertEqual(T.subArch, nil)
    T = Triple("mipsn32el")
    XCTAssertEqual(T.arch, Triple.Arch.mips64el)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabin32)
    XCTAssertEqual(T.subArch, nil)

    T = Triple("mips64-unknown-linux-gnuabin32")
    XCTAssertEqual(T.arch, Triple.Arch.mips64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabin32)
    XCTAssertEqual(T.subArch, nil)
    T = Triple("mipsn32")
    XCTAssertEqual(T.arch, Triple.Arch.mips64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabin32)
    XCTAssertEqual(T.subArch, nil)

    T = Triple("mipsisa64r6el-unknown-linux-gnuabin32")
    XCTAssertEqual(T.arch, Triple.Arch.mips64el)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabin32)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))
    T = Triple("mipsn32r6el")
    XCTAssertEqual(T.arch, Triple.Arch.mips64el)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabin32)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))

    T = Triple("mipsisa64r6-unknown-linux-gnuabin32")
    XCTAssertEqual(T.arch, Triple.Arch.mips64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabin32)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))
    T = Triple("mipsn32r6")
    XCTAssertEqual(T.arch, Triple.Arch.mips64)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnuabin32)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))

    T = Triple("mipsel-unknown-linux-gnu")
    XCTAssertEqual(T.arch, Triple.Arch.mipsel)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)
    XCTAssertEqual(T.subArch, nil)
    T = Triple("mipsel")
    XCTAssertEqual(T.arch, Triple.Arch.mipsel)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)
    XCTAssertEqual(T.subArch, nil)

    T = Triple("mips-unknown-linux-gnu")
    XCTAssertEqual(T.arch, Triple.Arch.mips)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)
    XCTAssertEqual(T.subArch, nil)
    T = Triple("mips")
    XCTAssertEqual(T.arch, Triple.Arch.mips)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)
    XCTAssertEqual(T.subArch, nil)

    T = Triple("mipsisa32r6el-unknown-linux-gnu")
    XCTAssertEqual(T.arch, Triple.Arch.mipsel)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))
    T = Triple("mipsr6el")
    XCTAssertEqual(T.arch, Triple.Arch.mipsel)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))
    T = Triple("mipsisa32r6el")
    XCTAssertEqual(T.arch, Triple.Arch.mipsel)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))

    T = Triple("mipsisa32r6-unknown-linux-gnu")
    XCTAssertEqual(T.arch, Triple.Arch.mips)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))
    T = Triple("mipsr6")
    XCTAssertEqual(T.arch, Triple.Arch.mips)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))
    T = Triple("mipsisa32r6")
    XCTAssertEqual(T.arch, Triple.Arch.mips)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)
    XCTAssertEqual(T.subArch, Triple.SubArch.mips(.r6))

    T = Triple("arm-oe-linux-gnueabi")
    XCTAssertEqual(T.arch, Triple.Arch.arm)
    XCTAssertEqual(T.vendor, Triple.Vendor.openEmbedded)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnueabi)

    T = Triple("aarch64-oe-linux")
    XCTAssertEqual(T.arch, Triple.Arch.aarch64)
    XCTAssertEqual(T.vendor, Triple.Vendor.openEmbedded)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, nil)
    XCTAssertEqual(T.arch?.is64Bit, true)

    T = Triple("arm64_32-apple-ios")
    XCTAssertEqual(T.arch, Triple.Arch.aarch64_32)
    XCTAssertEqual(T.os, Triple.OS.ios)
    XCTAssertEqual(T.environment, nil)
    XCTAssertEqual(T.arch?.is32Bit, true)

    T = Triple("armv7s-apple-ios")
    XCTAssertEqual(T.arch, Triple.Arch.arm)
    XCTAssertEqual(T.os, Triple.OS.ios)
    XCTAssertEqual(T.environment, nil)
    XCTAssertEqual(T.arch?.is32Bit, true)
    XCTAssertEqual(T.subArch, Triple.SubArch.arm(.v7s))

    T = Triple("xscale-none-linux-gnueabi")
    XCTAssertEqual(T.arch, Triple.Arch.arm)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.vendor, nil)
    XCTAssertEqual(T.environment, Triple.Environment.gnueabi)
    XCTAssertEqual(T.subArch, Triple.SubArch.arm(.v5e))

    T = Triple("thumbv7-pc-linux-gnu")
    XCTAssertEqual(T.arch, Triple.Arch.thumb)
    XCTAssertEqual(T.vendor, Triple.Vendor.pc)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)

    T = Triple("thumbv3-pc-linux-gnu")
    XCTAssertEqual(T.arch, nil)
    XCTAssertEqual(T.vendor, Triple.Vendor.pc)
    XCTAssertEqual(T.os, Triple.OS.linux)
    XCTAssertEqual(T.environment, Triple.Environment.gnu)

    T = Triple("huh")
    XCTAssertEqual(T.arch, nil)
  }

  func assertNormalizesEqual(
    _ input: String, _ expected: String,
    file: StaticString = #file, line: UInt = #line
  ) {
    XCTAssertEqual(Triple(input, normalizing: true).triple, expected,
                   "normalizing '\(input)'", file: file, line: line)
  }

  func normalize(_ string: String) -> String {
    Triple(string, normalizing: true).triple
  }

  // Normalization test cases adapted from the llvm::Triple unit tests.

  func testNormalizeSimple() {
    assertNormalizesEqual("", "unknown")
    assertNormalizesEqual("-", "unknown-unknown")
    assertNormalizesEqual("--", "unknown-unknown-unknown")
    assertNormalizesEqual("---", "unknown-unknown-unknown-unknown")
    assertNormalizesEqual("----", "unknown-unknown-unknown-unknown-unknown")

    assertNormalizesEqual("a", "a")
    assertNormalizesEqual("a-b", "a-b")
    assertNormalizesEqual("a-b-c", "a-b-c")
    assertNormalizesEqual("a-b-c-d", "a-b-c-d")

    assertNormalizesEqual("i386-b-c", "i386-b-c")
    assertNormalizesEqual("a-i386-c", "i386-a-c")
    assertNormalizesEqual("a-b-i386", "i386-a-b")
    assertNormalizesEqual("a-b-c-i386", "i386-a-b-c")

    assertNormalizesEqual("a-pc-c", "a-pc-c")
    assertNormalizesEqual("pc-b-c", "unknown-pc-b-c")
    assertNormalizesEqual("a-b-pc", "a-pc-b")
    assertNormalizesEqual("a-b-c-pc", "a-pc-b-c")

    assertNormalizesEqual("a-b-linux", "a-b-linux")
    assertNormalizesEqual("linux-b-c", "unknown-unknown-linux-b-c")
    assertNormalizesEqual("a-linux-c", "a-unknown-linux-c")

    assertNormalizesEqual("a-pc-i386", "i386-pc-a")
    assertNormalizesEqual("-pc-i386", "i386-pc-unknown")
    assertNormalizesEqual("linux-pc-c", "unknown-pc-linux-c")
    assertNormalizesEqual("linux-pc-", "unknown-pc-linux")

    assertNormalizesEqual("i386", "i386")
    assertNormalizesEqual("pc", "unknown-pc")
    assertNormalizesEqual("linux", "unknown-unknown-linux")

    assertNormalizesEqual("x86_64-gnu-linux", "x86_64-unknown-linux-gnu")
  }

  func testNormalizePermute() {
    // Check that normalizing a permutated set of valid components returns a
    // triple with the unpermuted components.
    //
    // We don't check every possible combination. For the set of architectures A,
    // vendors V, operating systems O, and environments E, that would require |A|
    // * |V| * |O| * |E| * 4! tests. Instead we check every option for any given
    // slot and make sure it gets normalized to the correct position from every
    // permutation. This should cover the core logic while being a tractable
    // number of tests at (|A| + |V| + |O| + |E|) * 4!.
    let template = [
      Triple.Arch.aarch64.rawValue,
      Triple.Vendor.amd.rawValue,
      Triple.OS.aix.rawValue,
      Triple.Environment.android.rawValue
    ]

    func testPermutations(with replacement: String, at i: Int, of count: Int) {
      var components = Array(template[..<count])
      components[i] = replacement
      let expected = components.joined(separator: "-")

      forAllPermutations(count) { indices in
        let permutation =
            indices.map { i in components[i] }.joined(separator: "-")
        XCTAssertEqual(normalize(permutation), expected)
      }
    }

    for arch in Triple.Arch.allCases {
      testPermutations(with: arch.rawValue, at: 0, of: 3)
      testPermutations(with: arch.rawValue, at: 0, of: 4)
    }
    for vendor in Triple.Vendor.allCases {
      testPermutations(with: vendor.rawValue, at: 1, of: 3)
      testPermutations(with: vendor.rawValue, at: 1, of: 4)
    }
    for os in Triple.OS.allCases where os != .win32 {
      testPermutations(with: os.rawValue, at: 2, of: 3)
      testPermutations(with: os.rawValue, at: 2, of: 4)
    }
    for env in Triple.Environment.allCases {
      testPermutations(with: env.rawValue, at: 3, of: 4)
    }
  }

  func testNormalizeSpecialCases() {
    // Various real-world funky triples.  The value returned by GCC's config.sub
    // is given in the comment.
    assertNormalizesEqual("i386-mingw32",
              "i386-unknown-windows-gnu") // i386-pc-mingw32
    assertNormalizesEqual("x86_64-linux-gnu",
              "x86_64-unknown-linux-gnu") // x86_64-pc-linux-gnu
    assertNormalizesEqual("i486-linux-gnu",
              "i486-unknown-linux-gnu") // i486-pc-linux-gnu
    assertNormalizesEqual("i386-redhat-linux",
              "i386-redhat-linux") // i386-redhat-linux-gnu
    assertNormalizesEqual("i686-linux",
              "i686-unknown-linux") // i686-pc-linux-gnu
    assertNormalizesEqual("arm-none-eabi",
              "arm-unknown-none-eabi") // arm-none-eabi
    assertNormalizesEqual("wasm32-wasi",
              "wasm32-unknown-wasi") // wasm32-unknown-wasi
    assertNormalizesEqual("wasm64-wasi",
              "wasm64-unknown-wasi") // wasm64-unknown-wasi
  }

  func testNormalizeWindows() {
    assertNormalizesEqual("i686-pc-win32", "i686-pc-windows-msvc")
    assertNormalizesEqual("i686-win32", "i686-unknown-windows-msvc")
    assertNormalizesEqual("i686-pc-mingw32", "i686-pc-windows-gnu")
    assertNormalizesEqual("i686-mingw32", "i686-unknown-windows-gnu")
    assertNormalizesEqual("i686-pc-mingw32-w64", "i686-pc-windows-gnu")
    assertNormalizesEqual("i686-mingw32-w64", "i686-unknown-windows-gnu")
    assertNormalizesEqual("i686-pc-cygwin", "i686-pc-windows-cygnus")
    assertNormalizesEqual("i686-cygwin", "i686-unknown-windows-cygnus")

    assertNormalizesEqual("x86_64-pc-win32", "x86_64-pc-windows-msvc")
    assertNormalizesEqual("x86_64-win32", "x86_64-unknown-windows-msvc")
    assertNormalizesEqual("x86_64-pc-mingw32", "x86_64-pc-windows-gnu")
    assertNormalizesEqual("x86_64-mingw32", "x86_64-unknown-windows-gnu")
    assertNormalizesEqual("x86_64-pc-mingw32-w64",
              "x86_64-pc-windows-gnu")
    assertNormalizesEqual("x86_64-mingw32-w64",
              "x86_64-unknown-windows-gnu")

    assertNormalizesEqual("i686-pc-win32-elf", "i686-pc-windows-elf")
    assertNormalizesEqual("i686-win32-elf", "i686-unknown-windows-elf")
    assertNormalizesEqual("i686-pc-win32-macho", "i686-pc-windows-macho")
    assertNormalizesEqual("i686-win32-macho",
              "i686-unknown-windows-macho")

    assertNormalizesEqual("x86_64-pc-win32-elf", "x86_64-pc-windows-elf")
    assertNormalizesEqual("x86_64-win32-elf",
              "x86_64-unknown-windows-elf")
    assertNormalizesEqual("x86_64-pc-win32-macho",
              "x86_64-pc-windows-macho")
    assertNormalizesEqual("x86_64-win32-macho",
              "x86_64-unknown-windows-macho")

    assertNormalizesEqual("i686-pc-windows-cygnus",
              "i686-pc-windows-cygnus")
    assertNormalizesEqual("i686-pc-windows-gnu", "i686-pc-windows-gnu")
    assertNormalizesEqual("i686-pc-windows-itanium",
              "i686-pc-windows-itanium")
    assertNormalizesEqual("i686-pc-windows-msvc", "i686-pc-windows-msvc")

    assertNormalizesEqual("i686-pc-windows-elf-elf",
              "i686-pc-windows-elf")

    assertNormalizesEqual("i686-unknown-windows-coff", "i686-unknown-windows-coff")
    assertNormalizesEqual("x86_64-unknown-windows-coff", "x86_64-unknown-windows-coff")
  }

  func testNormalizeARM() {
    assertNormalizesEqual("armv6-netbsd-eabi",
              "armv6-unknown-netbsd-eabi")
    assertNormalizesEqual("armv7-netbsd-eabi",
              "armv7-unknown-netbsd-eabi")
    assertNormalizesEqual("armv6eb-netbsd-eabi",
              "armv6eb-unknown-netbsd-eabi")
    assertNormalizesEqual("armv7eb-netbsd-eabi",
              "armv7eb-unknown-netbsd-eabi")
    assertNormalizesEqual("armv6-netbsd-eabihf",
              "armv6-unknown-netbsd-eabihf")
    assertNormalizesEqual("armv7-netbsd-eabihf",
              "armv7-unknown-netbsd-eabihf")
    assertNormalizesEqual("armv6eb-netbsd-eabihf",
              "armv6eb-unknown-netbsd-eabihf")
    assertNormalizesEqual("armv7eb-netbsd-eabihf",
              "armv7eb-unknown-netbsd-eabihf")

    assertNormalizesEqual("armv7-suse-linux-gnueabi",
              "armv7-suse-linux-gnueabihf")

    var T: Triple
    T = Triple("armv6--netbsd-eabi")
    XCTAssertEqual(.arm, T.arch)
    T = Triple("armv6eb--netbsd-eabi")
    XCTAssertEqual(.armeb, T.arch)
    T = Triple("arm64--netbsd-eabi")
    XCTAssertEqual(.aarch64, T.arch)
    T = Triple("aarch64_be--netbsd-eabi")
    XCTAssertEqual(.aarch64_be, T.arch)
    T = Triple("armv7-suse-linux-gnueabihf")
    XCTAssertEqual(.gnueabihf, T.environment)
  }

  func testOSVersion() {
    var T: Triple
    var V: Triple.Version?

    T = Triple("i386-apple-darwin9")
    XCTAssertTrue(T.os?.isMacOSX)
    XCTAssertFalse(T.os?.isiOS)
    XCTAssertFalse(T.arch?.is16Bit)
    XCTAssertTrue(T.arch?.is32Bit)
    XCTAssertFalse(T.arch?.is64Bit)
    V = T._macOSVersion
    XCTAssertEqual(V?.major, 10)
    XCTAssertEqual(V?.minor, 5)
    XCTAssertEqual(V?.micro, 0)
    V = T._iOSVersion
    XCTAssertEqual(V?.major, 5)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)

    T = Triple("x86_64-apple-darwin9")
    XCTAssertTrue(T.os?.isMacOSX)
    XCTAssertFalse(T.os?.isiOS)
    XCTAssertFalse(T.arch?.is16Bit)
    XCTAssertFalse(T.arch?.is32Bit)
    XCTAssertTrue(T.arch?.is64Bit)
    V = T._macOSVersion
    XCTAssertEqual(V?.major, 10)
    XCTAssertEqual(V?.minor, 5)
    XCTAssertEqual(V?.micro, 0)
    V = T._iOSVersion
    XCTAssertEqual(V?.major, 5)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)

    T = Triple("x86_64-apple-darwin20")
    XCTAssertTrue(T.os?.isMacOSX)
    XCTAssertFalse(T.os?.isiOS)
    XCTAssertFalse(T.arch?.is16Bit)
    XCTAssertFalse(T.arch?.is32Bit)
    XCTAssertTrue(T.arch?.is64Bit)
    V = T._macOSVersion
    XCTAssertEqual(V?.major, 11)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)
    V = T._iOSVersion
    XCTAssertEqual(V?.major, 5)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)

    T = Triple("x86_64-apple-darwin21")
    XCTAssertTrue(T.os?.isMacOSX)
    XCTAssertFalse(T.os?.isiOS)
    XCTAssertFalse(T.arch?.is16Bit)
    XCTAssertFalse(T.arch?.is32Bit)
    XCTAssertTrue(T.arch?.is64Bit)
    V = T._macOSVersion
    XCTAssertEqual(V?.major, 12)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)
    V = T._iOSVersion
    XCTAssertEqual(V?.major, 5)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)

    T = Triple("x86_64-apple-macosx")
    XCTAssertTrue(T.os?.isMacOSX)
    XCTAssertFalse(T.os?.isiOS)
    XCTAssertFalse(T.arch?.is16Bit)
    XCTAssertFalse(T.arch?.is32Bit)
    XCTAssertTrue(T.arch?.is64Bit)
    V = T._macOSVersion
    XCTAssertEqual(V?.major, 10)
    XCTAssertEqual(V?.minor, 4)
    XCTAssertEqual(V?.micro, 0)
    V = T._iOSVersion
    XCTAssertEqual(V?.major, 5)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)

    T = Triple("x86_64-apple-macosx10.7")
    XCTAssertTrue(T.os?.isMacOSX)
    XCTAssertFalse(T.os?.isiOS)
    XCTAssertFalse(T.arch?.is16Bit)
    XCTAssertFalse(T.arch?.is32Bit)
    XCTAssertTrue(T.arch?.is64Bit)
    V = T._macOSVersion
    XCTAssertEqual(V?.major, 10)
    XCTAssertEqual(V?.minor, 7)
    XCTAssertEqual(V?.micro, 0)
    V = T._iOSVersion
    XCTAssertEqual(V?.major, 5)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)

    T = Triple("x86_64-apple-macosx11.0")
    XCTAssertTrue(T.os?.isMacOSX)
    XCTAssertFalse(T.os?.isiOS)
    XCTAssertFalse(T.arch?.is16Bit)
    XCTAssertFalse(T.arch?.is32Bit)
    XCTAssertTrue(T.arch?.is64Bit)
    V = T._macOSVersion
    XCTAssertEqual(V?.major, 11)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)
    V = T._iOSVersion
    XCTAssertEqual(V?.major, 5)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)

    T = Triple("x86_64-apple-macosx11.1")
    XCTAssertTrue(T.os?.isMacOSX)
    XCTAssertFalse(T.os?.isiOS)
    XCTAssertFalse(T.arch?.is16Bit)
    XCTAssertFalse(T.arch?.is32Bit)
    XCTAssertTrue(T.arch?.is64Bit)
    V = T._macOSVersion
    XCTAssertEqual(V?.major, 11)
    XCTAssertEqual(V?.minor, 1)
    XCTAssertEqual(V?.micro, 0)
    V = T._iOSVersion
    XCTAssertEqual(V?.major, 5)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)

    T = Triple("x86_64-apple-macosx12.0")
    XCTAssertTrue(T.os?.isMacOSX)
    XCTAssertFalse(T.os?.isiOS)
    XCTAssertFalse(T.arch?.is16Bit)
    XCTAssertFalse(T.arch?.is32Bit)
    XCTAssertTrue(T.arch?.is64Bit)
    V = T._macOSVersion
    XCTAssertEqual(V?.major, 12)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)
    V = T._iOSVersion
    XCTAssertEqual(V?.major, 5)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)

    T = Triple("armv7-apple-ios")
    XCTAssertFalse(T.os?.isMacOSX)
    XCTAssertTrue(T.os?.isiOS)
    XCTAssertEqual(T.arch?.is16Bit, false)
    XCTAssertEqual(T.arch?.is32Bit, true)
    XCTAssertEqual(T.arch?.is64Bit, false)
    V = T.version(for: .macOS)
    XCTAssertEqual(V?.major, 10)
    XCTAssertEqual(V?.minor, 4)
    XCTAssertEqual(V?.micro, 0)
    V = T.version(for: .iOS(.device))
    XCTAssertEqual(V?.major, 5)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)

    T = Triple("armv7-apple-ios7.0")
    XCTAssertFalse(T.os?.isMacOSX)
    XCTAssertTrue(T.os?.isiOS)
    XCTAssertEqual(T.arch?.is16Bit, false)
    XCTAssertEqual(T.arch?.is32Bit, true)
    XCTAssertEqual(T.arch?.is64Bit, false)
    V = T.version(for: .macOS)
    XCTAssertEqual(V?.major, 10)
    XCTAssertEqual(V?.minor, 4)
    XCTAssertEqual(V?.micro, 0)
    V = T.version(for: .iOS(.device))
    XCTAssertEqual(V?.major, 7)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)
    XCTAssertFalse(T._isSimulatorEnvironment)

    T = Triple("x86_64-apple-ios10.3-simulator")
    XCTAssertTrue(T.os?.isiOS)
    V = T._iOSVersion
    XCTAssertEqual(V?.major, 10)
    XCTAssertEqual(V?.minor, 3)
    XCTAssertEqual(V?.micro, 0)
    XCTAssertTrue(T._isSimulatorEnvironment)
    XCTAssertFalse(T.isMacCatalyst)

    T = Triple("x86_64-apple-ios13.0-macabi")
    XCTAssertTrue(T.os?.isiOS)
    V = T._iOSVersion
    XCTAssertEqual(V?.major, 13)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)
    XCTAssertEqual(T.environment, .macabi)
    XCTAssertTrue(T.isMacCatalyst)
    XCTAssertFalse(T._isSimulatorEnvironment)

    T = Triple("x86_64-apple-ios12.0")
    XCTAssertTrue(T.os?.isiOS)
    V = T._iOSVersion
    XCTAssertEqual(V?.major, 12)
    XCTAssertEqual(V?.minor, 0)
    XCTAssertEqual(V?.micro, 0)
    XCTAssertFalse(T._isSimulatorEnvironment)
    XCTAssertFalse(T.isMacCatalyst)
  }

  func testFileFormat() {
    XCTAssertEqual(.elf, Triple("i686-unknown-linux-gnu").objectFormat)
    XCTAssertEqual(.elf, Triple("x86_64-unknown-linux-gnu").objectFormat)
    XCTAssertEqual(.elf, Triple("x86_64-gnu-linux").objectFormat)
    XCTAssertEqual(.elf, Triple("i686-unknown-freebsd").objectFormat)
    XCTAssertEqual(.elf, Triple("i686-unknown-netbsd").objectFormat)
    XCTAssertEqual(.elf, Triple("i686--win32-elf").objectFormat)
    XCTAssertEqual(.elf, Triple("i686---elf").objectFormat)

    XCTAssertEqual(.macho, Triple("i686-apple-macosx").objectFormat)
    XCTAssertEqual(.macho, Triple("i686-apple-ios").objectFormat)
    XCTAssertEqual(.macho, Triple("i686---macho").objectFormat)

    XCTAssertEqual(.coff, Triple("i686--win32").objectFormat)
    XCTAssertEqual(.coff, Triple("i686-unknown-windows-coff").objectFormat)

    XCTAssertEqual(.elf, Triple("i686-pc-windows-msvc-elf").objectFormat)
    XCTAssertEqual(.elf, Triple("i686-pc-cygwin-elf").objectFormat)

    XCTAssertEqual(.wasm, Triple("wasm32-unknown-unknown").objectFormat)
    XCTAssertEqual(.wasm, Triple("wasm64-unknown-unknown").objectFormat)
    XCTAssertEqual(.wasm, Triple("wasm32-wasi").objectFormat)
    XCTAssertEqual(.wasm, Triple("wasm64-wasi").objectFormat)
    XCTAssertEqual(.wasm, Triple("wasm32-unknown-wasi").objectFormat)
    XCTAssertEqual(.wasm, Triple("wasm64-unknown-wasi").objectFormat)

    XCTAssertEqual(.wasm,
              Triple("wasm32-unknown-unknown-wasm").objectFormat)
    XCTAssertEqual(.wasm,
              Triple("wasm64-unknown-unknown-wasm").objectFormat)
    XCTAssertEqual(.wasm,
              Triple("wasm32-wasi-wasm").objectFormat)
    XCTAssertEqual(.wasm,
              Triple("wasm64-wasi-wasm").objectFormat)
    XCTAssertEqual(.wasm,
              Triple("wasm32-unknown-wasi-wasm").objectFormat)
    XCTAssertEqual(.wasm,
              Triple("wasm64-unknown-wasi-wasm").objectFormat)

    XCTAssertEqual(.xcoff, Triple("powerpc-ibm-aix").objectFormat)
    XCTAssertEqual(.xcoff, Triple("powerpc64-ibm-aix").objectFormat)
    XCTAssertEqual(.xcoff, Triple("powerpc---xcoff").objectFormat)
    XCTAssertEqual(.xcoff, Triple("powerpc64---xcoff").objectFormat)

//    let MSVCNormalized = Triple("i686-pc-windows-msvc-elf", normalizing: true)
//    XCTAssertEqual(.elf, MSVCNormalized.objectFormat)

//    let GNUWindowsNormalized = Triple("i686-pc-windows-gnu-elf", normalizing: true)
//    XCTAssertEqual(.elf, GNUWindowsNormalized.objectFormat)

//    let CygnusNormalized = Triple("i686-pc-windows-cygnus-elf", normalizing: true)
//    XCTAssertEqual(.elf, CygnusNormalized.objectFormat)

    let CygwinNormalized = Triple("i686-pc-cygwin-elf", normalizing: true)
    XCTAssertEqual(.elf, CygwinNormalized.objectFormat)

//    var T = Triple("")
//    T.setObjectFormat(.ELF)
//    XCTAssertEqual(.ELF, T.objectFormat)
//
//    T.setObjectFormat(.MachO)
//    XCTAssertEqual(.MachO, T.objectFormat)
//
//    T.setObjectFormat(.XCOFF)
//    XCTAssertEqual(.XCOFF, T.objectFormat)
  }

  static let jetPacks = Triple.FeatureAvailability(
    macOS: .available(since: .init(10, 50, 0)),
    iOS: .available(since: .init(50, 0, 0)),
    tvOS: .available(since: .init(50, 0, 0)),
    watchOS: .available(since: .init(50, 0, 0)),
    nonDarwin: true
  )

  func assertDarwinPlatformCorrect<T: Equatable>(
    _ triple: Triple,
    case match: (DarwinPlatform) -> T?,
    environment: T,
    macOSVersion: Triple.Version?,
    iOSVersion: Triple.Version?,
    watchOSVersion: Triple.Version?,
    shouldHaveJetPacks: Bool,
    file: StaticString = #file, line: UInt = #line
  ) {
    guard let platform = triple.darwinPlatform else {
      XCTFail("Not a Darwin platform: \(triple)", file: file, line: line)
      return
    }

    guard let matchedEnvironment = match(platform) else {
      XCTFail("Unexpected case: \(platform) from \(triple)",
        file: file, line: line)
      return
    }

    XCTAssertEqual(matchedEnvironment, environment,
                   "environment == .simulator", file: file, line: line)

    if let macOSVersion = macOSVersion {
      XCTAssertEqual(triple.version(for: .macOS), macOSVersion,
                     "macOS version", file: file, line: line)
    }
    if let iOSVersion = iOSVersion {
      XCTAssertEqual(triple.version(for: .iOS(.device)), iOSVersion,
                     "iOS device version", file: file, line: line)
      XCTAssertEqual(triple.version(for: .iOS(.simulator)), iOSVersion,
                     "iOS simulator version", file: file, line: line)
      XCTAssertEqual(triple.version(for: .tvOS(.device)), iOSVersion,
                     "tvOS device version", file: file, line: line)
      XCTAssertEqual(triple.version(for: .tvOS(.simulator)), iOSVersion,
                     "tvOS simulator version", file: file, line: line)
    }
    if let watchOSVersion = watchOSVersion {
      XCTAssertEqual(triple.version(for: .watchOS(.device)), watchOSVersion,
                     "watchOS device version", file: file, line: line)
      XCTAssertEqual(triple.version(for: .watchOS(.simulator)), watchOSVersion,
                     "watchOS simulator version", file: file, line: line)
    }

    XCTAssertEqual(triple.supports(Self.jetPacks), shouldHaveJetPacks,
                   "FeatureAvailability version check", file: file, line: line)
  }

  func testDarwinPlatform() {
    let nonDarwin = Triple("x86_64-unknown-linux")
    XCTAssertNil(nonDarwin.darwinPlatform)
    XCTAssertTrue(nonDarwin.supports(Self.jetPacks))

    func macOS(_ platform: DarwinPlatform) -> DarwinPlatform.Environment? {
      if case .macOS = platform { return .device } else { return nil }
    }
    func iOS(_ platform: DarwinPlatform) -> DarwinPlatform.Environment? {
      if case .iOS(let env) = platform { return env } else { return nil }
    }
    func tvOS(_ platform: DarwinPlatform) -> DarwinPlatform.EnvironmentWithoutCatalyst? {
      if case .tvOS(let env) = platform { return env } else { return nil }
    }
    func watchOS(_ platform: DarwinPlatform) -> DarwinPlatform.EnvironmentWithoutCatalyst? {
      if case .watchOS(let env) = platform { return env } else { return nil }
    }

    let macOS1 = Triple("x86_64-apple-macosx10.12")
    let macOS2 = Triple("i386-apple-macos10.50.0")
    let macOS3 = Triple("i386-apple-macos10.60.9")
    let macOS4 = Triple("i386-apple-darwin19")

    assertDarwinPlatformCorrect(macOS1,
                                case: macOS,
                                environment: .device,
                                macOSVersion: .init(10, 12, 0),
                                iOSVersion: .init(5, 0, 0),
                                watchOSVersion: .init(2, 0, 0),
                                shouldHaveJetPacks: false)
    assertDarwinPlatformCorrect(macOS2,
                                case: macOS,
                                environment: .device,
                                macOSVersion: .init(10, 50, 0),
                                iOSVersion: .init(5, 0, 0),
                                watchOSVersion: .init(2, 0, 0),
                                shouldHaveJetPacks: true)
    assertDarwinPlatformCorrect(macOS3,
                                case: macOS,
                                environment: .device,
                                macOSVersion: .init(10, 60, 9),
                                iOSVersion: .init(5, 0, 0),
                                watchOSVersion: .init(2, 0, 0),
                                shouldHaveJetPacks: true)
    assertDarwinPlatformCorrect(macOS4,
                                case: macOS,
                                environment: .device,
                                macOSVersion: .init(10, 15, 0),
                                iOSVersion: .init(5, 0, 0),
                                watchOSVersion: .init(2, 0, 0),
                                shouldHaveJetPacks: false)

    let iOS1 = Triple("x86_64-apple-ios13.0-simulator")
    let iOS2 = Triple("powerpc-apple-ios50.0") // FIXME: should test with ARM
    let iOS3 = Triple("x86_64-apple-ios60.0-macabi")

    assertDarwinPlatformCorrect(iOS1,
                                case: iOS,
                                environment: .simulator,
                                macOSVersion: .init(10, 4, 0),
                                iOSVersion: .init(13, 0, 0),
                                watchOSVersion: nil,
                                shouldHaveJetPacks: false)
    assertDarwinPlatformCorrect(iOS2,
                                case: iOS,
                                environment: .device,
                                macOSVersion: .init(10, 4, 0),
                                iOSVersion: .init(50, 0, 0),
                                watchOSVersion: nil,
                                shouldHaveJetPacks: true)
    assertDarwinPlatformCorrect(iOS3,
                                case: iOS,
                                environment: .catalyst,
                                macOSVersion: .init(10, 4, 0),
                                iOSVersion: .init(60, 0, 0),
                                watchOSVersion: nil,
                                shouldHaveJetPacks: true)

    let tvOS1 = Triple("x86_64-apple-tvos13.0-simulator")
    let tvOS2 = Triple("powerpc-apple-tvos50.0") // FIXME: should test with ARM
    let tvOS3 = Triple("x86_64-apple-tvos60.0-simulator")

    assertDarwinPlatformCorrect(tvOS1,
                                case: tvOS,
                                environment: .simulator,
                                macOSVersion: .init(10, 4, 0),
                                iOSVersion: .init(13, 0, 0),
                                watchOSVersion: nil,
                                shouldHaveJetPacks: false)
    assertDarwinPlatformCorrect(tvOS2,
                                case: tvOS,
                                environment: .device,
                                macOSVersion: .init(10, 4, 0),
                                iOSVersion: .init(50, 0, 0),
                                watchOSVersion: nil,
                                shouldHaveJetPacks: true)
    assertDarwinPlatformCorrect(tvOS3,
                                case: tvOS,
                                environment: .simulator,
                                macOSVersion: .init(10, 4, 0),
                                iOSVersion: .init(60, 0, 0),
                                watchOSVersion: nil,
                                shouldHaveJetPacks: true)

    let watchOS1 = Triple("x86_64-apple-watchos6.0-simulator")
    let watchOS2 = Triple("powerpc-apple-watchos50.0") // FIXME: should test with ARM
    let watchOS3 = Triple("x86_64-apple-watchos60.0-simulator")

    assertDarwinPlatformCorrect(watchOS1,
                                case: watchOS,
                                environment: .simulator,
                                macOSVersion: .init(10, 4, 0),
                                iOSVersion: nil,
                                watchOSVersion: .init(6, 0, 0),
                                shouldHaveJetPacks: false)
    assertDarwinPlatformCorrect(watchOS2,
                                case: watchOS,
                                environment: .device,
                                macOSVersion: .init(10, 4, 0),
                                iOSVersion: nil,
                                watchOSVersion: .init(50, 0, 0),
                                shouldHaveJetPacks: true)
    assertDarwinPlatformCorrect(watchOS3,
                                case: watchOS,
                                environment: .simulator,
                                macOSVersion: .init(10, 4, 0),
                                iOSVersion: nil,
                                watchOSVersion: .init(60, 0, 0),
                                shouldHaveJetPacks: true)
  }

  func testToolchainSelection() {
    let diagnostics = DiagnosticsEngine()
    struct None { }

    func assertToolchain<T>(
      _ rawTriple: String,
      _ expectedToolchain: T.Type?,
      file: StaticString = #filePath,
      line: UInt = #line
    ) {
      do {
        let triple = Triple(rawTriple)
        let actual = try triple.toolchainType(diagnostics)
        if None.self is T.Type {
          XCTFail(
            "Expected None but found \(actual) for triple \(rawTriple).",
            file: file,
            line: line)
        } else {
          XCTAssertTrue(
            actual is T.Type,
            "Expected \(T.self) but found \(actual) for triple \(rawTriple).",
            file: file,
            line: line)
        }
      } catch {
        if None.self is T.Type {
          // Good
        } else {
          XCTFail(
            "Expected \(T.self) but found None for triple \(rawTriple).",
            file: file,
            line: line)
        }
      }
    }

    assertToolchain("i386-apple-darwin", DarwinToolchain.self)
    assertToolchain("i386-pc-hurd-gnu", None.self)
    assertToolchain("x86_64-pc-linux-gnu", GenericUnixToolchain.self)
    assertToolchain("x86_64-pc-linux-musl", GenericUnixToolchain.self)
    assertToolchain("powerpc-bgp-linux", GenericUnixToolchain.self)
    assertToolchain("powerpc-bgp-cnk", None.self)
    assertToolchain("ppc-bgp-linux", GenericUnixToolchain.self)
    assertToolchain("ppc32-bgp-linux", GenericUnixToolchain.self)
    assertToolchain("powerpc64-bgq-linux", GenericUnixToolchain.self)
    assertToolchain("ppc64-bgq-linux", GenericUnixToolchain.self)
    assertToolchain("powerpc-ibm-aix", None.self)
    assertToolchain("powerpc64-ibm-aix", None.self)
    assertToolchain("powerpc-dunno-notsure", None.self)
    assertToolchain("arm-none-none-eabi", GenericUnixToolchain.self)
    assertToolchain("arm-none-unknown-eabi", None.self)
    assertToolchain("arm-none-linux-musleabi", GenericUnixToolchain.self)
    assertToolchain("armv6hl-none-linux-gnueabi", GenericUnixToolchain.self)
    assertToolchain("armv7hl-none-linux-gnueabi", GenericUnixToolchain.self)
    assertToolchain("amdil-unknown-unknown", None.self)
    assertToolchain("amdil64-unknown-unknown", None.self)
    assertToolchain("hsail-unknown-unknown", None.self)
    assertToolchain("hsail64-unknown-unknown", None.self)
    assertToolchain("sparcel-unknown-unknown", None.self)
    assertToolchain("spir-unknown-unknown", None.self)
    assertToolchain("spir64-unknown-unknown", None.self)
    assertToolchain("x86_64-unknown-ananas", None.self)
    assertToolchain("x86_64-unknown-cloudabi", None.self)
    assertToolchain("x86_64-unknown-fuchsia", None.self)
    assertToolchain("x86_64-unknown-hermit", None.self)
    assertToolchain("wasm32-unknown-unknown", None.self)
    assertToolchain("wasm32-unknown-wasi", WebAssemblyToolchain.self)
    assertToolchain("wasm64-unknown-unknown", None.self)
    assertToolchain("wasm64-unknown-wasi", WebAssemblyToolchain.self)
    assertToolchain("avr-unknown-unknown", None.self)
    assertToolchain("avr", None.self)
    assertToolchain("lanai-unknown-unknown", None.self)
    assertToolchain("lanai", None.self)
    assertToolchain("amdgcn-mesa-mesa3d", None.self)
    assertToolchain("amdgcn-amd-amdhsa", None.self)
    assertToolchain("amdgcn-amd-amdpal", None.self)
    assertToolchain("riscv32-unknown-unknown", None.self)
    assertToolchain("riscv64-unknown-linux", GenericUnixToolchain.self)
    assertToolchain("riscv64-unknown-freebsd", GenericUnixToolchain.self)
    assertToolchain("armv7hl-suse-linux-gnueabi", GenericUnixToolchain.self)
    assertToolchain("i586-pc-haiku", GenericUnixToolchain.self)
    assertToolchain("x86_64-unknown-haiku", GenericUnixToolchain.self)
    assertToolchain("m68k-suse-linux-gnu", GenericUnixToolchain.self)
    assertToolchain("mips-mti-linux-gnu", GenericUnixToolchain.self)
    assertToolchain("mipsel-img-linux-gnu", GenericUnixToolchain.self)
    assertToolchain("mips64-mti-linux-gnu", GenericUnixToolchain.self)
    assertToolchain("mips64el-img-linux-gnu", GenericUnixToolchain.self)
    assertToolchain("mips64el-img-linux-gnuabin32", GenericUnixToolchain.self)
    assertToolchain("mips64el", None.self)
    assertToolchain("mips64", None.self)
    assertToolchain("mips64-unknown-linux-gnuabi64", GenericUnixToolchain.self)
    assertToolchain("mips64-unknown-linux-gnuabin32", GenericUnixToolchain.self)
    assertToolchain("mipsn32", None.self)
    assertToolchain("mipsn32r6", None.self)
    assertToolchain("mipsel-unknown-linux-gnu", GenericUnixToolchain.self)
    assertToolchain("mipsel", None.self)
    assertToolchain("mips-unknown-linux-gnu", GenericUnixToolchain.self)
    assertToolchain("mips", None.self)
    assertToolchain("mipsr6el", None.self)
    assertToolchain("mipsisa32r6el", None.self)
    assertToolchain("mipsisa32r6-unknown-linux-gnu", GenericUnixToolchain.self)
    assertToolchain("mipsr6", None.self)
    assertToolchain("mipsisa32r6", None.self)
    assertToolchain("arm-oe-linux-gnueabi", GenericUnixToolchain.self)
    assertToolchain("aarch64-oe-linux", GenericUnixToolchain.self)
    assertToolchain("x86_64-apple-tvos13.0-simulator", DarwinToolchain.self)
    assertToolchain("arm64_32-apple-ios", DarwinToolchain.self)
    assertToolchain("armv7s-apple-ios", DarwinToolchain.self)
    assertToolchain("armv7em-unknown-none-macho", GenericUnixToolchain.self)
    assertToolchain("armv7em-apple-none-macho", DarwinToolchain.self)
    assertToolchain("armv7em-apple-none", DarwinToolchain.self)
    assertToolchain("xscale-none-linux-gnueabi", GenericUnixToolchain.self)
    assertToolchain("thumbv7-pc-linux-gnu", GenericUnixToolchain.self)
    assertToolchain("thumbv3-pc-linux-gnu", GenericUnixToolchain.self)
    assertToolchain("i686-pc-windows-msvc", WindowsToolchain.self)
    assertToolchain("i686-unknown-windows-msvc", WindowsToolchain.self)
    assertToolchain("i686-pc-windows-gnu", WindowsToolchain.self)
    assertToolchain("i686-unknown-windows-gnu", WindowsToolchain.self)
    assertToolchain("i686-pc-windows-gnu", WindowsToolchain.self)
    assertToolchain("i686-unknown-windows-gnu", WindowsToolchain.self)
    assertToolchain("i686-pc-windows-cygnus", WindowsToolchain.self)
    assertToolchain("i686-unknown-windows-cygnus", WindowsToolchain.self)
  }
}

extension Triple.Version: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) {
    self.init(parse: value)
  }
}

// Variants of XCTAssertTrue and False which accept Optional<Bool>.

func XCTAssertTrue(
  _ expression: @autoclosure () throws -> Bool?,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #file, line: UInt = #line
) {
  XCTAssertEqual(try expression(), true, message(), file: file, line: line)
}

func XCTAssertFalse(
  _ expression: @autoclosure () throws -> Bool?,
  _ message: @autoclosure () -> String = "",
  file: StaticString = #file, line: UInt = #line
) {
  XCTAssertEqual(try expression(), false, message(), file: file, line: line)
}

