//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@_spi(Testing) import SwiftDriver
import Testing

import class TSCBasic.DiagnosticsEngine

@Suite struct TripleTests {
  @Test func basics() throws {
    #expect(Triple("").arch == nil)
    #expect(Triple("kalimba").arch == .kalimba)
    #expect(Triple("m68k-unknown-linux-gnu").arch == .m68k)
    #expect(Triple("x86_64-apple-macosx").arch == .x86_64)
    #expect(Triple("blah-apple").arch == nil)
    #expect(Triple("x86_64-apple-macosx").vendor == .apple)
    #expect(Triple("x86_64-apple-macosx").os == .macosx)
    #expect(Triple("x86_64-apple-macosx-macabi").environment == .macabi)
    #expect(Triple("x86_64-apple-macosx-macabixxmacho").objectFormat == .macho)
    #expect(Triple("mipsn32").environment == .gnuabin32)

    #expect(Triple("x86_64-unknown-mylinux").osName == "mylinux")
    #expect(Triple("x86_64-unknown-mylinux-abi").osName == "mylinux")
    #expect(Triple("x86_64-unknown").osName == "")

    #expect(Triple("x86_64-apple-macosx10.13").osVersion == "10.13.0")
    #expect(Triple("x86_64-apple-macosx1x.13").osVersion == "0.13.0")
    #expect(Triple("x86_64-apple-macosx10.13.5-abi").osVersion == "10.13.5")

    #expect(Triple("arm64-unknown-none").arch == .aarch64)
    #expect(Triple("arm64-unknown-none").vendor == nil)
    #expect(Triple("arm64-unknown-none").os == .noneOS)
    #expect(Triple("arm64-unknown-none").environment == nil)
    #expect(Triple("arm64-unknown-none").objectFormat == .elf)

    #expect(Triple("xtensa-unknown-none").objectFormat == .elf)

    #expect(Triple("arm64-apple-none-macho").arch == .aarch64)
    #expect(Triple("arm64-apple-none-macho").vendor == .apple)
    #expect(Triple("arm64-apple-none-macho").os == .noneOS)
    #expect(Triple("arm64-apple-none-macho").environment == nil)
    #expect(Triple("arm64-apple-none-macho").objectFormat == .macho)

    #expect(Triple("x86_64-unknown-freebsd14.1").arch == .x86_64)
    #expect(Triple("x86_64-unknown-freebsd14.1").vendor == nil)
    #expect(Triple("x86_64-unknown-freebsd14.1").os == .freeBSD)
    #expect(Triple("x86_64-unknown-freebsd14.1").osNameUnversioned == "freebsd")
    #expect(Triple("x86_64-unknown-freebsd14.1").objectFormat == .elf)
  }

  @Test func basicParsing() {
    var T: Triple

    T = Triple("")
    #expect(T.archName == "")
    #expect(T.vendorName == "")
    #expect(T.osName == "")
    #expect(T.environmentName == "")

    T = Triple("-")
    #expect(T.archName == "")
    #expect(T.vendorName == "")
    #expect(T.osName == "")
    #expect(T.environmentName == "")

    T = Triple("--")
    #expect(T.archName == "")
    #expect(T.vendorName == "")
    #expect(T.osName == "")
    #expect(T.environmentName == "")

    T = Triple("---")
    #expect(T.archName == "")
    #expect(T.vendorName == "")
    #expect(T.osName == "")
    #expect(T.environmentName == "")

    T = Triple("----")
    #expect(T.archName == "")
    #expect(T.vendorName == "")
    #expect(T.osName == "")
    #expect(T.environmentName == "-")

    T = Triple("a")
    #expect(T.archName == "a")
    #expect(T.vendorName == "")
    #expect(T.osName == "")
    #expect(T.environmentName == "")

    T = Triple("a-b")
    #expect(T.archName == "a")
    #expect(T.vendorName == "b")
    #expect(T.osName == "")
    #expect(T.environmentName == "")

    T = Triple("a-b-c")
    #expect(T.archName == "a")
    #expect(T.vendorName == "b")
    #expect(T.osName == "c")
    #expect(T.environmentName == "")

    T = Triple("a-b-c-d")
    #expect(T.archName == "a")
    #expect(T.vendorName == "b")
    #expect(T.osName == "c")
    #expect(T.environmentName == "d")
  }

  @Test func parsedIDs() {
    var T: Triple

    T = Triple("i386-apple-darwin")
    #expect(T.arch == Triple.Arch.x86)
    #expect(T.vendor == Triple.Vendor.apple)
    #expect(T.os == Triple.OS.darwin)
    #expect(T.environment == nil)

    T = Triple("arm64-apple-firmware1.0")
    #expect(T.arch == Triple.Arch.aarch64)
    #expect(T.vendor == Triple.Vendor.apple)
    #expect(T.os == Triple.OS.firmware)
    #expect(T.environment == nil)
    #expect(T.objectFormat == .macho)
    #expect(T.isDarwin)

    T = Triple("i386-pc-elfiamcu")
    #expect(T.arch == Triple.Arch.x86)
    #expect(T.vendor == Triple.Vendor.pc)
    #expect(T.os == Triple.OS.elfiamcu)
    #expect(T.environment == nil)

    T = Triple("i386-pc-contiki-unknown")
    #expect(T.arch == Triple.Arch.x86)
    #expect(T.vendor == Triple.Vendor.pc)
    #expect(T.os == Triple.OS.contiki)
    #expect(T.environment == nil)

    T = Triple("i386-pc-hurd-gnu")
    #expect(T.arch == Triple.Arch.x86)
    #expect(T.vendor == Triple.Vendor.pc)
    #expect(T.os == Triple.OS.hurd)
    #expect(T.environment == Triple.Environment.gnu)

    T = Triple("x86_64-pc-linux-gnu")
    #expect(T.arch == Triple.Arch.x86_64)
    #expect(T.vendor == Triple.Vendor.pc)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnu)

    T = Triple("x86_64-pc-linux-musl")
    #expect(T.arch == Triple.Arch.x86_64)
    #expect(T.vendor == Triple.Vendor.pc)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.musl)

    T = Triple("powerpc-bgp-linux")
    #expect(T.arch == Triple.Arch.ppc)
    #expect(T.vendor == Triple.Vendor.bgp)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == nil)

    T = Triple("powerpc-bgp-cnk")
    #expect(T.arch == Triple.Arch.ppc)
    #expect(T.vendor == Triple.Vendor.bgp)
    #expect(T.os == Triple.OS.cnk)
    #expect(T.environment == nil)

    T = Triple("ppc-bgp-linux")
    #expect(T.arch == Triple.Arch.ppc)
    #expect(T.vendor == Triple.Vendor.bgp)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == nil)

    T = Triple("ppc32-bgp-linux")
    #expect(T.arch == Triple.Arch.ppc)
    #expect(T.vendor == Triple.Vendor.bgp)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == nil)

    T = Triple("powerpc64-bgq-linux")
    #expect(T.arch == Triple.Arch.ppc64)
    #expect(T.vendor == Triple.Vendor.bgq)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == nil)

    T = Triple("ppc64-bgq-linux")
    #expect(T.arch == Triple.Arch.ppc64)
    #expect(T.vendor == Triple.Vendor.bgq)
    #expect(T.os == Triple.OS.linux)

    T = Triple("powerpc-ibm-aix")
    #expect(T.arch == Triple.Arch.ppc)
    #expect(T.vendor == Triple.Vendor.ibm)
    #expect(T.os == Triple.OS.aix)
    #expect(T.environment == nil)

    T = Triple("powerpc64-ibm-aix")
    #expect(T.arch == Triple.Arch.ppc64)
    #expect(T.vendor == Triple.Vendor.ibm)
    #expect(T.os == Triple.OS.aix)
    #expect(T.environment == nil)

    T = Triple("powerpc-dunno-notsure")
    #expect(T.arch == Triple.Arch.ppc)
    #expect(T.vendor == nil)
    #expect(T.os == nil)
    #expect(T.environment == nil)

    T = Triple("arm-none-none-eabi")
    #expect(T.arch == Triple.Arch.arm)
    #expect(T.subArch == nil)
    #expect(T.vendor == nil)
    #expect(T.os == .noneOS)
    #expect(T.environment == Triple.Environment.eabi)

    T = Triple("arm-none-unknown-eabi")
    #expect(T.arch == Triple.Arch.arm)
    #expect(T.subArch == nil)
    #expect(T.vendor == nil)
    #expect(T.os == nil)
    #expect(T.environment == Triple.Environment.eabi)

    T = Triple("arm-none-linux-musleabi")
    #expect(T.arch == Triple.Arch.arm)
    #expect(T.subArch == nil)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.musleabi)

    T = Triple("armv6hl-none-linux-gnueabi")
    #expect(T.arch == Triple.Arch.arm)
    #expect(T.subArch == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnueabi)

    T = Triple("armv7hl-none-linux-gnueabi")
    #expect(T.arch == Triple.Arch.arm)
    #expect(T.subArch == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnueabi)

    T = Triple("armv7em-apple-none-macho")
    #expect(T.arch == Triple.Arch.arm)
    #expect(T.subArch == Triple.SubArch.arm(.v7em))
    #expect(T.vendor == .apple)
    #expect(T.os == Triple.OS.noneOS)
    #expect(T.environment == nil)
    #expect(T.objectFormat == Triple.ObjectFormat.macho)

    T = Triple("amdil-unknown-unknown")
    #expect(T.arch == Triple.Arch.amdil)
    #expect(T.vendor == nil)
    #expect(T.os == nil)

    T = Triple("amdil64-unknown-unknown")
    #expect(T.arch == Triple.Arch.amdil64)
    #expect(T.vendor == nil)
    #expect(T.os == nil)

    T = Triple("hsail-unknown-unknown")
    #expect(T.arch == Triple.Arch.hsail)
    #expect(T.vendor == nil)
    #expect(T.os == nil)

    T = Triple("hsail64-unknown-unknown")
    #expect(T.arch == Triple.Arch.hsail64)
    #expect(T.vendor == nil)
    #expect(T.os == nil)

    T = Triple("m68k-unknown-unknown")
    #expect(T.arch == Triple.Arch.m68k)
    #expect(T.vendor == nil)
    #expect(T.os == nil)

    T = Triple("sparcel-unknown-unknown")
    #expect(T.arch == Triple.Arch.sparcel)
    #expect(T.vendor == nil)
    #expect(T.os == nil)

    T = Triple("spir-unknown-unknown")
    #expect(T.arch == Triple.Arch.spir)
    #expect(T.vendor == nil)
    #expect(T.os == nil)

    T = Triple("spir64-unknown-unknown")
    #expect(T.arch == Triple.Arch.spir64)
    #expect(T.vendor == nil)
    #expect(T.os == nil)

    T = Triple("x86_64-unknown-ananas")
    #expect(T.arch == Triple.Arch.x86_64)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.ananas)
    #expect(T.environment == nil)

    T = Triple("x86_64-unknown-cloudabi")
    #expect(T.arch == Triple.Arch.x86_64)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.cloudABI)
    #expect(T.environment == nil)

    T = Triple("x86_64-unknown-fuchsia")
    #expect(T.arch == Triple.Arch.x86_64)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.fuchsia)
    #expect(T.environment == nil)

    T = Triple("x86_64-unknown-hermit")
    #expect(T.arch == Triple.Arch.x86_64)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.hermitcore)
    #expect(T.environment == nil)

    T = Triple("wasm32-unknown-unknown")
    #expect(T.arch == Triple.Arch.wasm32)
    #expect(T.vendor == nil)
    #expect(T.os == nil)
    #expect(T.environment == nil)

    T = Triple("wasm32-unknown-wasi")
    #expect(T.arch == Triple.Arch.wasm32)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.wasi)
    #expect(T.environment == nil)

    T = Triple("wasm64-unknown-unknown")
    #expect(T.arch == Triple.Arch.wasm64)
    #expect(T.vendor == nil)
    #expect(T.os == nil)
    #expect(T.environment == nil)

    T = Triple("wasm64-unknown-wasi")
    #expect(T.arch == Triple.Arch.wasm64)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.wasi)
    #expect(T.environment == nil)

    T = Triple("avr-unknown-unknown")
    #expect(T.arch == Triple.Arch.avr)
    #expect(T.vendor == nil)
    #expect(T.os == nil)
    #expect(T.environment == nil)

    T = Triple("avr")
    #expect(T.arch == Triple.Arch.avr)
    #expect(T.vendor == nil)
    #expect(T.os == nil)
    #expect(T.environment == nil)

    T = Triple("lanai-unknown-unknown")
    #expect(T.arch == Triple.Arch.lanai)
    #expect(T.vendor == nil)
    #expect(T.os == nil)
    #expect(T.environment == nil)

    T = Triple("lanai")
    #expect(T.arch == Triple.Arch.lanai)
    #expect(T.vendor == nil)
    #expect(T.os == nil)
    #expect(T.environment == nil)

    T = Triple("amdgcn-mesa-mesa3d")
    #expect(T.arch == Triple.Arch.amdgcn)
    #expect(T.vendor == Triple.Vendor.mesa)
    #expect(T.os == Triple.OS.mesa3d)
    #expect(T.environment == nil)

    T = Triple("amdgcn-amd-amdhsa")
    #expect(T.arch == Triple.Arch.amdgcn)
    #expect(T.vendor == Triple.Vendor.amd)
    #expect(T.os == Triple.OS.amdhsa)
    #expect(T.environment == nil)

    T = Triple("amdgcn-amd-amdpal")
    #expect(T.arch == Triple.Arch.amdgcn)
    #expect(T.vendor == Triple.Vendor.amd)
    #expect(T.os == Triple.OS.amdpal)
    #expect(T.environment == nil)

    T = Triple("riscv32-unknown-unknown")
    #expect(T.arch == Triple.Arch.riscv32)
    #expect(T.vendor == nil)
    #expect(T.os == nil)
    #expect(T.environment == nil)

    T = Triple("riscv64-unknown-linux")
    #expect(T.arch == Triple.Arch.riscv64)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == nil)

    T = Triple("riscv64-unknown-freebsd")
    #expect(T.arch == Triple.Arch.riscv64)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.freeBSD)
    #expect(T.environment == nil)

    T = Triple("armv7hl-suse-linux-gnueabi")
    #expect(T.arch == Triple.Arch.arm)
    #expect(T.vendor == Triple.Vendor.suse)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnueabi)

    T = Triple("i586-pc-haiku")
    #expect(T.arch == Triple.Arch.x86)
    #expect(T.vendor == Triple.Vendor.pc)
    #expect(T.os == Triple.OS.haiku)
    #expect(T.environment == nil)

    T = Triple("x86_64-unknown-haiku")
    #expect(T.arch == Triple.Arch.x86_64)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.haiku)
    #expect(T.environment == nil)

    T = Triple("m68k-suse-linux-gnu")
    #expect(T.arch == Triple.Arch.m68k)
    #expect(T.vendor == Triple.Vendor.suse)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnu)

    T = Triple("mips-mti-linux-gnu")
    #expect(T.arch == Triple.Arch.mips)
    #expect(T.vendor == Triple.Vendor.mipsTechnologies)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnu)

    T = Triple("mipsel-img-linux-gnu")
    #expect(T.arch == Triple.Arch.mipsel)
    #expect(T.vendor == Triple.Vendor.imaginationTechnologies)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnu)

    T = Triple("mips64-mti-linux-gnu")
    #expect(T.arch == Triple.Arch.mips64)
    #expect(T.vendor == Triple.Vendor.mipsTechnologies)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnu)

    T = Triple("mips64el-img-linux-gnu")
    #expect(T.arch == Triple.Arch.mips64el)
    #expect(T.vendor == Triple.Vendor.imaginationTechnologies)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnu)

    T = Triple("mips64el-img-linux-gnuabin32")
    #expect(T.arch == Triple.Arch.mips64el)
    #expect(T.vendor == Triple.Vendor.imaginationTechnologies)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnuabin32)

    T = Triple("mips64el-unknown-linux-gnuabi64")
    #expect(T.arch == Triple.Arch.mips64el)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnuabi64)
    #expect(T.subArch == nil)
    T = Triple("mips64el")
    #expect(T.arch == Triple.Arch.mips64el)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnuabi64)
    #expect(T.subArch == nil)

    T = Triple("mips64-unknown-linux-gnuabi64")
    #expect(T.arch == Triple.Arch.mips64)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnuabi64)
    #expect(T.subArch == nil)
    T = Triple("mips64")
    #expect(T.arch == Triple.Arch.mips64)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnuabi64)
    #expect(T.subArch == nil)

    T = Triple("mipsisa64r6el-unknown-linux-gnuabi64")
    #expect(T.arch == Triple.Arch.mips64el)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnuabi64)
    #expect(T.subArch == Triple.SubArch.mips(.r6))
    T = Triple("mips64r6el")
    #expect(T.arch == Triple.Arch.mips64el)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnuabi64)
    #expect(T.subArch == Triple.SubArch.mips(.r6))
    T = Triple("mipsisa64r6el")
    #expect(T.arch == Triple.Arch.mips64el)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnuabi64)
    #expect(T.subArch == Triple.SubArch.mips(.r6))

    T = Triple("mipsisa64r6-unknown-linux-gnuabi64")
    #expect(T.arch == Triple.Arch.mips64)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnuabi64)
    #expect(T.subArch == Triple.SubArch.mips(.r6))
    T = Triple("mips64r6")
    #expect(T.arch == Triple.Arch.mips64)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnuabi64)
    #expect(T.subArch == Triple.SubArch.mips(.r6))
    T = Triple("mipsisa64r6")
    #expect(T.arch == Triple.Arch.mips64)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnuabi64)
    #expect(T.subArch == Triple.SubArch.mips(.r6))

    T = Triple("mips64el-unknown-linux-gnuabin32")
    #expect(T.arch == Triple.Arch.mips64el)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnuabin32)
    #expect(T.subArch == nil)
    T = Triple("mipsn32el")
    #expect(T.arch == Triple.Arch.mips64el)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnuabin32)
    #expect(T.subArch == nil)

    T = Triple("mips64-unknown-linux-gnuabin32")
    #expect(T.arch == Triple.Arch.mips64)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnuabin32)
    #expect(T.subArch == nil)
    T = Triple("mipsn32")
    #expect(T.arch == Triple.Arch.mips64)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnuabin32)
    #expect(T.subArch == nil)

    T = Triple("mipsisa64r6el-unknown-linux-gnuabin32")
    #expect(T.arch == Triple.Arch.mips64el)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnuabin32)
    #expect(T.subArch == Triple.SubArch.mips(.r6))
    T = Triple("mipsn32r6el")
    #expect(T.arch == Triple.Arch.mips64el)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnuabin32)
    #expect(T.subArch == Triple.SubArch.mips(.r6))

    T = Triple("mipsisa64r6-unknown-linux-gnuabin32")
    #expect(T.arch == Triple.Arch.mips64)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnuabin32)
    #expect(T.subArch == Triple.SubArch.mips(.r6))
    T = Triple("mipsn32r6")
    #expect(T.arch == Triple.Arch.mips64)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnuabin32)
    #expect(T.subArch == Triple.SubArch.mips(.r6))

    T = Triple("mipsel-unknown-linux-gnu")
    #expect(T.arch == Triple.Arch.mipsel)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnu)
    #expect(T.subArch == nil)
    T = Triple("mipsel")
    #expect(T.arch == Triple.Arch.mipsel)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnu)
    #expect(T.subArch == nil)

    T = Triple("mips-unknown-linux-gnu")
    #expect(T.arch == Triple.Arch.mips)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnu)
    #expect(T.subArch == nil)
    T = Triple("mips")
    #expect(T.arch == Triple.Arch.mips)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnu)
    #expect(T.subArch == nil)

    T = Triple("mipsisa32r6el-unknown-linux-gnu")
    #expect(T.arch == Triple.Arch.mipsel)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnu)
    #expect(T.subArch == Triple.SubArch.mips(.r6))
    T = Triple("mipsr6el")
    #expect(T.arch == Triple.Arch.mipsel)
    #expect(T.vendor == nil)
    #expect(T.subArch == Triple.SubArch.mips(.r6))
    T = Triple("mipsisa32r6el")
    #expect(T.arch == Triple.Arch.mipsel)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnu)
    #expect(T.subArch == Triple.SubArch.mips(.r6))

    T = Triple("mipsisa32r6-unknown-linux-gnu")
    #expect(T.arch == Triple.Arch.mips)
    #expect(T.vendor == nil)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnu)
    #expect(T.subArch == Triple.SubArch.mips(.r6))
    T = Triple("mipsr6")
    #expect(T.arch == Triple.Arch.mips)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnu)
    #expect(T.subArch == Triple.SubArch.mips(.r6))
    T = Triple("mipsisa32r6")
    #expect(T.arch == Triple.Arch.mips)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnu)
    #expect(T.subArch == Triple.SubArch.mips(.r6))

    T = Triple("arm-oe-linux-gnueabi")
    #expect(T.arch == Triple.Arch.arm)
    #expect(T.vendor == Triple.Vendor.openEmbedded)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnueabi)

    T = Triple("aarch64-oe-linux")
    #expect(T.arch == Triple.Arch.aarch64)
    #expect(T.vendor == Triple.Vendor.openEmbedded)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == nil)
    #expect(T.arch?.is64Bit == true)

    T = Triple("arm64_32-apple-ios")
    #expect(T.arch == Triple.Arch.aarch64_32)
    #expect(T.os == Triple.OS.ios)
    #expect(T.environment == nil)
    #expect(T.arch?.is32Bit == true)

    T = Triple("armv7s-apple-ios")
    #expect(T.arch == Triple.Arch.arm)
    #expect(T.os == Triple.OS.ios)
    #expect(T.environment == nil)
    #expect(T.arch?.is32Bit == true)
    #expect(T.subArch == Triple.SubArch.arm(.v7s))

    T = Triple("xscale-none-linux-gnueabi")
    #expect(T.arch == Triple.Arch.arm)
    #expect(T.os == Triple.OS.linux)
    #expect(T.vendor == nil)
    #expect(T.environment == Triple.Environment.gnueabi)
    #expect(T.subArch == Triple.SubArch.arm(.v5e))

    T = Triple("thumbv7-pc-linux-gnu")
    #expect(T.arch == Triple.Arch.thumb)
    #expect(T.vendor == Triple.Vendor.pc)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnu)

    T = Triple("thumbv3-pc-linux-gnu")
    #expect(T.arch == nil)
    #expect(T.vendor == Triple.Vendor.pc)
    #expect(T.os == Triple.OS.linux)
    #expect(T.environment == Triple.Environment.gnu)

    T = Triple("huh")
    #expect(T.arch == nil)
  }

  func assertNormalizesEqual(
    _ input: String,
    _ expected: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(
      Triple(input, normalizing: true).triple == expected,
      "normalizing '\(input)'",
      sourceLocation: sourceLocation
    )
  }

  func normalize(_ string: String) -> String {
    Triple(string, normalizing: true).triple
  }

  // Normalization test cases adapted from the llvm::Triple unit tests.

  @Test func normalizeSimple() {
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

  @Test func normalizePermute() {
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
      Triple.Environment.android.rawValue,
    ]

    func testPermutations(with replacement: String, at i: Int, of count: Int) {
      var components = Array(template[..<count])
      components[i] = replacement
      let expected = components.joined(separator: "-")

      forAllPermutations(count) { indices in
        let permutation =
          indices.map { i in components[i] }.joined(separator: "-")
        #expect(normalize(permutation) == expected)
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

  @Test func normalizeSpecialCases() {
    // Various real-world funky triples.  The value returned by GCC's config.sub
    // is given in the comment.
    assertNormalizesEqual(
      "i386-mingw32",
      "i386-unknown-windows-gnu"
    )  // i386-pc-mingw32
    assertNormalizesEqual(
      "x86_64-linux-gnu",
      "x86_64-unknown-linux-gnu"
    )  // x86_64-pc-linux-gnu
    assertNormalizesEqual(
      "i486-linux-gnu",
      "i486-unknown-linux-gnu"
    )  // i486-pc-linux-gnu
    assertNormalizesEqual(
      "i386-redhat-linux",
      "i386-redhat-linux"
    )  // i386-redhat-linux-gnu
    assertNormalizesEqual(
      "i686-linux",
      "i686-unknown-linux"
    )  // i686-pc-linux-gnu
    assertNormalizesEqual(
      "arm-none-eabi",
      "arm-unknown-none-eabi"
    )  // arm-none-eabi
    assertNormalizesEqual(
      "wasm32-wasi",
      "wasm32-unknown-wasi"
    )  // wasm32-unknown-wasi
    assertNormalizesEqual(
      "wasm64-wasi",
      "wasm64-unknown-wasi"
    )  // wasm64-unknown-wasi
  }

  @Test func normalizeWindows() {
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
    assertNormalizesEqual(
      "x86_64-pc-mingw32-w64",
      "x86_64-pc-windows-gnu"
    )
    assertNormalizesEqual(
      "x86_64-mingw32-w64",
      "x86_64-unknown-windows-gnu"
    )

    assertNormalizesEqual("i686-pc-win32-elf", "i686-pc-windows-elf")
    assertNormalizesEqual("i686-win32-elf", "i686-unknown-windows-elf")
    assertNormalizesEqual("i686-pc-win32-macho", "i686-pc-windows-macho")
    assertNormalizesEqual(
      "i686-win32-macho",
      "i686-unknown-windows-macho"
    )

    assertNormalizesEqual("x86_64-pc-win32-elf", "x86_64-pc-windows-elf")
    assertNormalizesEqual(
      "x86_64-win32-elf",
      "x86_64-unknown-windows-elf"
    )
    assertNormalizesEqual(
      "x86_64-pc-win32-macho",
      "x86_64-pc-windows-macho"
    )
    assertNormalizesEqual(
      "x86_64-win32-macho",
      "x86_64-unknown-windows-macho"
    )

    assertNormalizesEqual(
      "i686-pc-windows-cygnus",
      "i686-pc-windows-cygnus"
    )
    assertNormalizesEqual("i686-pc-windows-gnu", "i686-pc-windows-gnu")
    assertNormalizesEqual(
      "i686-pc-windows-itanium",
      "i686-pc-windows-itanium"
    )
    assertNormalizesEqual("i686-pc-windows-msvc", "i686-pc-windows-msvc")

    assertNormalizesEqual(
      "i686-pc-windows-elf-elf",
      "i686-pc-windows-elf"
    )

    assertNormalizesEqual("i686-unknown-windows-coff", "i686-unknown-windows-coff")
    assertNormalizesEqual("x86_64-unknown-windows-coff", "x86_64-unknown-windows-coff")
  }

  @Test func normalizeARM() {
    assertNormalizesEqual(
      "armv6-netbsd-eabi",
      "armv6-unknown-netbsd-eabi"
    )
    assertNormalizesEqual(
      "armv7-netbsd-eabi",
      "armv7-unknown-netbsd-eabi"
    )
    assertNormalizesEqual(
      "armv6eb-netbsd-eabi",
      "armv6eb-unknown-netbsd-eabi"
    )
    assertNormalizesEqual(
      "armv7eb-netbsd-eabi",
      "armv7eb-unknown-netbsd-eabi"
    )
    assertNormalizesEqual(
      "armv6-netbsd-eabihf",
      "armv6-unknown-netbsd-eabihf"
    )
    assertNormalizesEqual(
      "armv7-netbsd-eabihf",
      "armv7-unknown-netbsd-eabihf"
    )
    assertNormalizesEqual(
      "armv6eb-netbsd-eabihf",
      "armv6eb-unknown-netbsd-eabihf"
    )
    assertNormalizesEqual(
      "armv7eb-netbsd-eabihf",
      "armv7eb-unknown-netbsd-eabihf"
    )

    assertNormalizesEqual(
      "armv7-suse-linux-gnueabi",
      "armv7-suse-linux-gnueabihf"
    )

    var T: Triple
    T = Triple("armv6--netbsd-eabi")
    #expect(.arm == T.arch)
    T = Triple("armv6eb--netbsd-eabi")
    #expect(.armeb == T.arch)
    T = Triple("arm64--netbsd-eabi")
    #expect(.aarch64 == T.arch)
    T = Triple("aarch64_be--netbsd-eabi")
    #expect(.aarch64_be == T.arch)
    T = Triple("armv7-suse-linux-gnueabihf")
    #expect(.gnueabihf == T.environment)
  }

  @Test func osVersion() {
    var T: Triple
    var V: Triple.Version?

    T = Triple("i386-apple-darwin9")
    #expect(T.os?.isMacOSX == true)
    #expect(T.os?.isiOS == false)
    #expect(T.arch?.is16Bit == false)
    #expect(T.arch?.is32Bit == true)
    #expect(T.arch?.is64Bit == false)
    V = T._macOSVersion
    #expect(V?.major == 10)
    #expect(V?.minor == 5)
    #expect(V?.micro == 0)
    V = T._iOSVersion
    #expect(V?.major == 5)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)

    T = Triple("x86_64-apple-darwin9")
    #expect(T.os?.isMacOSX == true)
    #expect(T.os?.isiOS == false)
    #expect(T.arch?.is16Bit == false)
    #expect(T.arch?.is32Bit == false)
    #expect(T.arch?.is64Bit == true)
    V = T._macOSVersion
    #expect(V?.major == 10)
    #expect(V?.minor == 5)
    #expect(V?.micro == 0)
    V = T._iOSVersion
    #expect(V?.major == 5)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)

    T = Triple("x86_64-apple-darwin20")
    #expect(T.os?.isMacOSX == true)
    #expect(T.os?.isiOS == false)
    #expect(T.arch?.is16Bit == false)
    #expect(T.arch?.is32Bit == false)
    #expect(T.arch?.is64Bit == true)
    V = T._macOSVersion
    #expect(V?.major == 11)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)
    V = T._iOSVersion
    #expect(V?.major == 5)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)

    T = Triple("x86_64-apple-darwin21")
    #expect(T.os?.isMacOSX == true)
    #expect(T.os?.isiOS == false)
    #expect(T.arch?.is16Bit == false)
    #expect(T.arch?.is32Bit == false)
    #expect(T.arch?.is64Bit == true)
    V = T._macOSVersion
    #expect(V?.major == 12)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)
    V = T._iOSVersion
    #expect(V?.major == 5)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)

    T = Triple("x86_64-apple-macosx")
    #expect(T.os?.isMacOSX == true)
    #expect(T.os?.isiOS == false)
    #expect(T.arch?.is16Bit == false)
    #expect(T.arch?.is32Bit == false)
    #expect(T.arch?.is64Bit == true)
    V = T._macOSVersion
    #expect(V?.major == 10)
    #expect(V?.minor == 4)
    #expect(V?.micro == 0)
    V = T._iOSVersion
    #expect(V?.major == 5)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)

    T = Triple("x86_64-apple-macosx10.7")
    #expect(T.os?.isMacOSX == true)
    #expect(T.os?.isiOS == false)
    #expect(T.arch?.is16Bit == false)
    #expect(T.arch?.is32Bit == false)
    #expect(T.arch?.is64Bit == true)
    V = T._macOSVersion
    #expect(V?.major == 10)
    #expect(V?.minor == 7)
    #expect(V?.micro == 0)
    V = T._iOSVersion
    #expect(V?.major == 5)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)

    T = Triple("x86_64-apple-macosx11.0")
    #expect(T.os?.isMacOSX == true)
    #expect(T.os?.isiOS == false)
    #expect(T.arch?.is16Bit == false)
    #expect(T.arch?.is32Bit == false)
    #expect(T.arch?.is64Bit == true)
    V = T._macOSVersion
    #expect(V?.major == 11)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)
    V = T._iOSVersion
    #expect(V?.major == 5)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)

    T = Triple("x86_64-apple-macosx11.1")
    #expect(T.os?.isMacOSX == true)
    #expect(T.os?.isiOS == false)
    #expect(T.arch?.is16Bit == false)
    #expect(T.arch?.is32Bit == false)
    #expect(T.arch?.is64Bit == true)
    V = T._macOSVersion
    #expect(V?.major == 11)
    #expect(V?.minor == 1)
    #expect(V?.micro == 0)
    V = T._iOSVersion
    #expect(V?.major == 5)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)

    T = Triple("x86_64-apple-macosx12.0")
    #expect(T.os?.isMacOSX == true)
    #expect(T.os?.isiOS == false)
    #expect(T.arch?.is16Bit == false)
    #expect(T.arch?.is32Bit == false)
    #expect(T.arch?.is64Bit == true)
    V = T._macOSVersion
    #expect(V?.major == 12)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)
    V = T._iOSVersion
    #expect(V?.major == 5)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)

    T = Triple("armv7-apple-ios")
    #expect(T.os?.isMacOSX == false)
    #expect(T.os?.isiOS == true)
    #expect(T.arch?.is16Bit == false)
    #expect(T.arch?.is32Bit == true)
    #expect(T.arch?.is64Bit == false)
    V = T.version(for: .macOS)
    #expect(V?.major == 10)
    #expect(V?.minor == 4)
    #expect(V?.micro == 0)
    V = T.version(for: .iOS(.device))
    #expect(V?.major == 5)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)

    T = Triple("armv7-apple-ios7.0")
    #expect(T.os?.isMacOSX == false)
    #expect(T.os?.isiOS == true)
    #expect(T.arch?.is16Bit == false)
    #expect(T.arch?.is32Bit == true)
    #expect(T.arch?.is64Bit == false)
    V = T.version(for: .macOS)
    #expect(V?.major == 10)
    #expect(V?.minor == 4)
    #expect(V?.micro == 0)
    V = T.version(for: .iOS(.device))
    #expect(V?.major == 7)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)
    #expect(T._isSimulatorEnvironment == false)

    T = Triple("x86_64-apple-ios10.3-simulator")
    #expect(T.os?.isiOS == true)
    V = T._iOSVersion
    #expect(V?.major == 10)
    #expect(V?.minor == 3)
    #expect(V?.micro == 0)
    #expect(T._isSimulatorEnvironment)
    #expect(!T.isMacCatalyst)

    T = Triple("x86_64-apple-ios13.0-macabi")
    #expect(T.os?.isiOS == true)
    V = T._iOSVersion
    #expect(V?.major == 13)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)
    #expect(T.environment == .macabi)
    #expect(T.isMacCatalyst)
    #expect(!T._isSimulatorEnvironment)

    T = Triple("x86_64-apple-ios12.0")
    #expect(T.os?.isiOS == true)
    #expect(T.os?.isTvOS == false)
    V = T._iOSVersion
    #expect(V?.major == 12)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)
    #expect(!T._isSimulatorEnvironment)
    #expect(!T.isMacCatalyst)

    T = Triple("x86_64-apple-tvos12.0")
    #expect(T.os?.isTvOS == true)
    #expect(T.os?.isiOS == false)
    V = T._tvOSVersion
    #expect(V?.major == 12)
    #expect(V?.minor == 0)
    #expect(V?.micro == 0)
    #expect(!T._isSimulatorEnvironment)
    #expect(!T.isMacCatalyst)
  }

  @Test func fileFormat() {
    #expect(.elf == Triple("i686-unknown-linux-gnu").objectFormat)
    #expect(.elf == Triple("x86_64-unknown-linux-gnu").objectFormat)
    #expect(.elf == Triple("x86_64-gnu-linux").objectFormat)
    #expect(.elf == Triple("i686-unknown-freebsd").objectFormat)
    #expect(.elf == Triple("i686-unknown-netbsd").objectFormat)
    #expect(.elf == Triple("i686--win32-elf").objectFormat)
    #expect(.elf == Triple("i686---elf").objectFormat)

    #expect(.macho == Triple("i686-apple-macosx").objectFormat)
    #expect(.macho == Triple("i686-apple-ios").objectFormat)
    #expect(.macho == Triple("arm64-apple-firmware1.0").objectFormat)
    #expect(.macho == Triple("i686---macho").objectFormat)

    #expect(.coff == Triple("i686--win32").objectFormat)
    #expect(.coff == Triple("i686-unknown-windows-coff").objectFormat)

    #expect(.elf == Triple("i686-pc-windows-msvc-elf").objectFormat)
    #expect(.elf == Triple("i686-pc-cygwin-elf").objectFormat)

    #expect(.wasm == Triple("wasm32-unknown-unknown").objectFormat)
    #expect(.wasm == Triple("wasm64-unknown-unknown").objectFormat)
    #expect(.wasm == Triple("wasm32-wasi").objectFormat)
    #expect(.wasm == Triple("wasm64-wasi").objectFormat)
    #expect(.wasm == Triple("wasm32-unknown-wasi").objectFormat)
    #expect(.wasm == Triple("wasm64-unknown-wasi").objectFormat)

    #expect(.wasm == Triple("wasm32-unknown-unknown-wasm").objectFormat)
    #expect(.wasm == Triple("wasm64-unknown-unknown-wasm").objectFormat)
    #expect(.wasm == Triple("wasm32-wasi-wasm").objectFormat)
    #expect(.wasm == Triple("wasm64-wasi-wasm").objectFormat)
    #expect(.wasm == Triple("wasm32-unknown-wasi-wasm").objectFormat)
    #expect(.wasm == Triple("wasm64-unknown-wasi-wasm").objectFormat)

    #expect(.xcoff == Triple("powerpc-ibm-aix").objectFormat)
    #expect(.xcoff == Triple("powerpc64-ibm-aix").objectFormat)
    #expect(.xcoff == Triple("powerpc---xcoff").objectFormat)
    #expect(.xcoff == Triple("powerpc64---xcoff").objectFormat)

    //    let MSVCNormalized = Triple("i686-pc-windows-msvc-elf", normalizing: true)
    //    #expect(.elf == MSVCNormalized.objectFormat)

    //    let GNUWindowsNormalized = Triple("i686-pc-windows-gnu-elf", normalizing: true)
    //    #expect(.elf == GNUWindowsNormalized.objectFormat)

    //    let CygnusNormalized = Triple("i686-pc-windows-cygnus-elf", normalizing: true)
    //    #expect(.elf == CygnusNormalized.objectFormat)

    let CygwinNormalized = Triple("i686-pc-cygwin-elf", normalizing: true)
    #expect(.elf == CygwinNormalized.objectFormat)

    //    var T = Triple("")
    //    T.setObjectFormat(.ELF)
    //    #expect(.ELF == T.objectFormat)
    //
    //    T.setObjectFormat(.MachO)
    //    #expect(.MachO == T.objectFormat)
    //
    //    T.setObjectFormat(.XCOFF)
    //    #expect(.XCOFF == T.objectFormat)
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
    tvOSVersion: Triple.Version?,
    watchOSVersion: Triple.Version?,
    shouldHaveJetPacks: Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    guard let platform = triple.darwinPlatform else {
      Issue.record("Not a Darwin platform: \(triple)", sourceLocation: sourceLocation)
      return
    }

    guard let matchedEnvironment = match(platform) else {
      Issue.record(
        "Unexpected case: \(platform) from \(triple)",
        sourceLocation: sourceLocation
      )
      return
    }

    #expect(
      matchedEnvironment == environment,
      "environment == .simulator",
      sourceLocation: sourceLocation
    )

    if let macOSVersion = macOSVersion {
      #expect(
        triple.version(for: .macOS) == macOSVersion,
        "macOS version",
        sourceLocation: sourceLocation
      )
    }
    if let iOSVersion = iOSVersion {
      #expect(
        triple.version(for: .iOS(.device)) == iOSVersion,
        "iOS device version",
        sourceLocation: sourceLocation
      )
      #expect(
        triple.version(for: .iOS(.simulator)) == iOSVersion,
        "iOS simulator version",
        sourceLocation: sourceLocation
      )
    }
    if let tvOSVersion = tvOSVersion {
      #expect(
        triple.version(for: .tvOS(.device)) == tvOSVersion,
        "tvOS device version",
        sourceLocation: sourceLocation
      )
      #expect(
        triple.version(for: .tvOS(.simulator)) == tvOSVersion,
        "tvOS simulator version",
        sourceLocation: sourceLocation
      )
    }
    if let watchOSVersion = watchOSVersion {
      #expect(
        triple.version(for: .watchOS(.device)) == watchOSVersion,
        "watchOS device version",
        sourceLocation: sourceLocation
      )
      #expect(
        triple.version(for: .watchOS(.simulator)) == watchOSVersion,
        "watchOS simulator version",
        sourceLocation: sourceLocation
      )
    }

    #expect(
      triple.supports(Self.jetPacks) == shouldHaveJetPacks,
      "FeatureAvailability version check",
      sourceLocation: sourceLocation
    )
  }

  @Test func darwinPlatform() {
    let nonDarwin = Triple("x86_64-unknown-linux")
    #expect(nonDarwin.darwinPlatform == nil)
    #expect(nonDarwin.supports(Self.jetPacks))

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
    func Firmware(_ platform: DarwinPlatform) -> DarwinPlatform.Environment? {
      if case .Firmware = platform { return .device } else { return nil }
    }

    let macOS1 = Triple("x86_64-apple-macosx10.12")
    let macOS2 = Triple("i386-apple-macos10.50.0")
    let macOS3 = Triple("i386-apple-macos10.60.9")
    let macOS4 = Triple("i386-apple-darwin19")

    assertDarwinPlatformCorrect(
      macOS1,
      case: macOS,
      environment: .device,
      macOSVersion: .init(10, 12, 0),
      iOSVersion: .init(5, 0, 0),
      tvOSVersion: .init(9, 0, 0),
      watchOSVersion: .init(2, 0, 0),
      shouldHaveJetPacks: false
    )
    assertDarwinPlatformCorrect(
      macOS2,
      case: macOS,
      environment: .device,
      macOSVersion: .init(10, 50, 0),
      iOSVersion: .init(5, 0, 0),
      tvOSVersion: .init(9, 0, 0),
      watchOSVersion: .init(2, 0, 0),
      shouldHaveJetPacks: true
    )
    assertDarwinPlatformCorrect(
      macOS3,
      case: macOS,
      environment: .device,
      macOSVersion: .init(10, 60, 9),
      iOSVersion: .init(5, 0, 0),
      tvOSVersion: .init(9, 0, 0),
      watchOSVersion: .init(2, 0, 0),
      shouldHaveJetPacks: true
    )
    assertDarwinPlatformCorrect(
      macOS4,
      case: macOS,
      environment: .device,
      macOSVersion: .init(10, 15, 0),
      iOSVersion: .init(5, 0, 0),
      tvOSVersion: .init(9, 0, 0),
      watchOSVersion: .init(2, 0, 0),
      shouldHaveJetPacks: false
    )

    let iOS1 = Triple("x86_64-apple-ios13.0-simulator")
    let iOS2 = Triple("powerpc-apple-ios50.0")  // FIXME: should test with ARM
    let iOS3 = Triple("x86_64-apple-ios60.0-macabi")

    assertDarwinPlatformCorrect(
      iOS1,
      case: iOS,
      environment: .simulator,
      macOSVersion: .init(10, 4, 0),
      iOSVersion: .init(13, 0, 0),
      tvOSVersion: nil,
      watchOSVersion: nil,
      shouldHaveJetPacks: false
    )
    assertDarwinPlatformCorrect(
      iOS2,
      case: iOS,
      environment: .device,
      macOSVersion: .init(10, 4, 0),
      iOSVersion: .init(50, 0, 0),
      tvOSVersion: nil,
      watchOSVersion: nil,
      shouldHaveJetPacks: true
    )
    assertDarwinPlatformCorrect(
      iOS3,
      case: iOS,
      environment: .catalyst,
      macOSVersion: .init(10, 4, 0),
      iOSVersion: .init(60, 0, 0),
      tvOSVersion: nil,
      watchOSVersion: nil,
      shouldHaveJetPacks: true
    )

    let tvOS1 = Triple("x86_64-apple-tvos13.0-simulator")
    let tvOS2 = Triple("powerpc-apple-tvos50.0")  // FIXME: should test with ARM
    let tvOS3 = Triple("x86_64-apple-tvos60.0-simulator")

    assertDarwinPlatformCorrect(
      tvOS1,
      case: tvOS,
      environment: .simulator,
      macOSVersion: .init(10, 4, 0),
      iOSVersion: .init(13, 0, 0),
      tvOSVersion: .init(13, 0, 0),
      watchOSVersion: nil,
      shouldHaveJetPacks: false
    )
    assertDarwinPlatformCorrect(
      tvOS2,
      case: tvOS,
      environment: .device,
      macOSVersion: .init(10, 4, 0),
      iOSVersion: .init(50, 0, 0),
      tvOSVersion: .init(50, 0, 0),
      watchOSVersion: nil,
      shouldHaveJetPacks: true
    )
    assertDarwinPlatformCorrect(
      tvOS3,
      case: tvOS,
      environment: .simulator,
      macOSVersion: .init(10, 4, 0),
      iOSVersion: .init(60, 0, 0),
      tvOSVersion: .init(60, 0, 0),
      watchOSVersion: nil,
      shouldHaveJetPacks: true
    )

    let watchOS1 = Triple("x86_64-apple-watchos6.0-simulator")
    let watchOS2 = Triple("powerpc-apple-watchos50.0")  // FIXME: should test with ARM
    let watchOS3 = Triple("x86_64-apple-watchos60.0-simulator")

    assertDarwinPlatformCorrect(
      watchOS1,
      case: watchOS,
      environment: .simulator,
      macOSVersion: .init(10, 4, 0),
      iOSVersion: nil,
      tvOSVersion: nil,
      watchOSVersion: .init(6, 0, 0),
      shouldHaveJetPacks: false
    )
    assertDarwinPlatformCorrect(
      watchOS2,
      case: watchOS,
      environment: .device,
      macOSVersion: .init(10, 4, 0),
      iOSVersion: nil,
      tvOSVersion: nil,
      watchOSVersion: .init(50, 0, 0),
      shouldHaveJetPacks: true
    )
    assertDarwinPlatformCorrect(
      watchOS3,
      case: watchOS,
      environment: .simulator,
      macOSVersion: .init(10, 4, 0),
      iOSVersion: nil,
      tvOSVersion: nil,
      watchOSVersion: .init(60, 0, 0),
      shouldHaveJetPacks: true
    )

    let firmware1 = Triple("arm64-apple-firmware1.0")
    let firmware2 = Triple("powerpc-apple-firmware1.0")

    assertDarwinPlatformCorrect(
      firmware1,
      case: Firmware,
      environment: .device,
      macOSVersion: .init(10, 4, 0),
      iOSVersion: nil,
      tvOSVersion: nil,
      watchOSVersion: nil,
      shouldHaveJetPacks: true
    )
    assertDarwinPlatformCorrect(
      firmware2,
      case: Firmware,
      environment: .device,
      macOSVersion: .init(10, 4, 0),
      iOSVersion: nil,
      tvOSVersion: nil,
      watchOSVersion: nil,
      shouldHaveJetPacks: true
    )
  }

  @Test func clangOSLibName() {
    #expect("darwin" == Triple("x86_64-apple-macosx").clangOSLibName)
    #expect("darwin" == Triple("arm64-apple-ios13.0").clangOSLibName)
    #expect("linux" == Triple("aarch64-unknown-linux-android24").clangOSLibName)
    #expect("wasi" == Triple("wasm32-unknown-wasi").clangOSLibName)
    #expect("wasip1" == Triple("wasm32-unknown-wasip1-threads").clangOSLibName)
    #expect("none" == Triple("arm64-unknown-none").clangOSLibName)
  }

  @Test func toolchainSelection() {
    let diagnostics = DiagnosticsEngine()
    struct None {}

    func assertToolchain<T>(
      _ rawTriple: String,
      _ expectedToolchain: T.Type?,
      sourceLocation: SourceLocation = #_sourceLocation
    ) {
      do {
        let triple = Triple(rawTriple)
        let actual = try triple.toolchainType(diagnostics)
        if None.self is T.Type {
          Issue.record(
            "Expected None but found \(actual) for triple \(rawTriple).",
            sourceLocation: sourceLocation
          )
        } else {
          #expect(
            actual is T.Type,
            "Expected \(T.self) but found \(actual) for triple \(rawTriple).",
            sourceLocation: sourceLocation
          )
        }
      } catch {
        if None.self is T.Type {
          // Good
        } else {
          Issue.record(
            "Expected \(T.self) but found None for triple \(rawTriple).",
            sourceLocation: sourceLocation
          )
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
    assertToolchain("arm64-apple-firmware1.0", DarwinToolchain.self)
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
