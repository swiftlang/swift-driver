//===--------------- makeOptions.cpp - Option Generation ------------------===//
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
#include <cassert>
#include <functional>
#include <iostream>
#include <map>
#include <set>
#include <string>
#include <vector>

#if __has_include("swift/Option/Options.inc")
#if __has_include("llvm/Option/OptTable.h")
#if __has_include("llvm/Option/Option.h")

#include "llvm/Option/OptTable.h"
#include "llvm/Option/Option.h"

enum class OptionKind {
  Group = 0,
  Input,
  Unknown,
  Flag,
  Joined,
  Separate,
  RemainingArgs,
  CommaJoined,
  JoinedOrSeparate,
  MultiArg,
};

//. The IDs of each option
enum class OptionID {
  Opt_INVALID = 0,
#define OPTION(...) LLVM_MAKE_OPT_ID_WITH_ID_PREFIX(Opt_, __VA_ARGS__),
#include "swift/Option/Options.inc"
#undef OPTION
};

enum SwiftFlags {
  HelpHidden       = (1 << 0),

  FrontendOption = (1 << 4),
  NoDriverOption = (1 << 5),
  NoInteractiveOption = (1 << 6),
  NoBatchOption = (1 << 7),
  DoesNotAffectIncrementalBuild = (1 << 8),
  AutolinkExtractOption = (1 << 9),
  ModuleWrapOption = (1 << 10),
  SwiftSynthesizeInterfaceOption = (1 << 11),
  ArgumentIsPath = (1 << 12),
  ModuleInterfaceOption = (1 << 13),
  SupplementaryOutput = (1 << 14),
  SwiftAPIExtractOption = (1 << 15),
  SwiftSymbolGraphExtractOption = (1 << 16),
  SwiftAPIDigesterOption = (1 << 17),
  NewDriverOnlyOption = (1 << 18),
  ModuleInterfaceOptionIgnorable = (1 << 19),
  ModuleInterfaceOptionIgnorablePrivate = (1 << 20),
  ArgumentIsFileList = (1 << 21),
  CacheInvariant = (1 << 22),
};

static std::set<std::string> swiftKeywords = { "internal", "static" };

/// Turns a snake_case_option_name into a camelCaseOptionName, and escapes
/// it if it's a keyword.
static std::string swiftify(const std::string &name) {
  std::string result;
  bool shouldUppercase = false;
  for (char c : name) {
    if (c == '_') {
      shouldUppercase = true;
      continue;
    }

    if (shouldUppercase && islower(c)) {
      result.push_back(toupper(c));
    } else {
      result.push_back(c);
    }

    shouldUppercase = false;
  }

  if (swiftKeywords.count(result) > 0)
    return "`" + result + "`";

  return result;
}

/// Raw option from the TableGen'd output of the Swift options.
struct RawOption {
  OptionID id;
  std::vector<llvm::StringRef> prefixes;
  const char *spelling;
  std::string idName;
  OptionKind kind;
  OptionID group;
  OptionID alias;
  unsigned flags;
  const char *helpText;
  const char *metaVar;
  unsigned numArgs;

  bool isGroup() const {
    return kind == OptionKind::Group;
  }

  bool isAlias() const {
    return alias != OptionID::Opt_INVALID;
  }

  bool isHidden() const {
    return flags & HelpHidden;
  }
};

#if defined(LLVM_VERSION_MAJOR) && LLVM_VERSION_MAJOR == 21

#define OPTTABLE_PREFIXES_TABLE_CODE
#include "swift/Option/Options.inc"
#undef OPTTABLE_PREFIXES_TABLE_CODE

#define OPTTABLE_STR_TABLE_CODE
#include "swift/Option/Options.inc"
#undef OPTTABLE_STR_TABLE_CODE

static std::vector<llvm::StringRef> getPrefixes(unsigned prefixesOffset) {
  unsigned numPrefixes = OptionPrefixesTable[prefixesOffset].value();

  std::vector<llvm::StringRef> prefixes;

  const unsigned firstOffsetIndex = prefixesOffset + 1;
  for (unsigned i = firstOffsetIndex, e = i + numPrefixes; i < e; ++i) {
    prefixes.push_back(OptionStrTable[OptionPrefixesTable[i]]);
  }

  return prefixes;
}

static const char *getPrefixedName(unsigned prefixedNameOffset) {
  return OptionStrTable[prefixedNameOffset].data();
}

#else // #if defined(LLVM_VERSION_MAJOR) && LLVM_VERSION_MAJOR == 21

#define PREFIX(NAME, VALUE) static constexpr llvm::StringLiteral NAME[] = VALUE;
#include "swift/Option/Options.inc"
#undef PREFIX

static std::vector<llvm::StringRef>
getPrefixes(llvm::ArrayRef<llvm::StringLiteral> prefixes) {
  return std::vector<llvm::StringRef>(prefixes.begin(), prefixes.end());
}

static const char *getPrefixedName(const char *prefixedName) {
  return prefixedName;
}

#endif // #if defined(LLVM_VERSION_MAJOR) && LLVM_VERSION_MAJOR == 21

static const RawOption rawOptions[] = {
#define OPTION(PREFIXES_OFFSET, PREFIXED_NAME_OFFSET, ID, KIND, GROUP, ALIAS,  \
               ALIASARGS, FLAGS, VISIBILITY, PARAM, HELPTEXT,                  \
               HELPTEXTFORVARIANTS, METAVAR, VALUES)                           \
  {OptionID::Opt_##ID,                                                         \
   getPrefixes(PREFIXES_OFFSET),                                               \
   getPrefixedName(PREFIXED_NAME_OFFSET),                                      \
   swiftify(#ID),                                                              \
   OptionKind::KIND,                                                           \
   OptionID::Opt_##GROUP,                                                      \
   OptionID::Opt_##ALIAS,                                                      \
   FLAGS,                                                                      \
   HELPTEXT,                                                                   \
   METAVAR,                                                                    \
   PARAM},
#include "swift/Option/Options.inc"
#undef OPTION
};

struct Group {
  std::string id;
  const char *name;
  const char *description;
};

static std::vector<Group> groups;
static std::map<OptionID, unsigned> groupIndexByID;
static std::map<OptionID, unsigned> optionIndexByID;

static std::string stringOrNil(const char *text) {
  if (!text)
    return "nil";

  return "\"" + std::string(text) + "\"";
}

static std::string stringOrNilLeftTrimmed(const char *text) {
  if (!text)
    return "nil";

  while (*text == ' ' && *text)
    ++text;

  return "\"" + std::string(text) + "\"";
}

void forEachOption(std::function<void(const RawOption &)> fn) {
  for (const auto &rawOption : rawOptions) {
    if (rawOption.isGroup())
      continue;

    if (rawOption.kind == OptionKind::Unknown)
      continue;

    fn(rawOption);
  }
}

void forEachSpelling(
    const RawOption &option,
    std::function<void(const std::string &spelling, bool isAlternateSpelling)>
        fn) {
  std::string spelling(option.spelling);
  auto &prefixes = option.prefixes;

  fn(spelling, /*isAlternateSpelling=*/false);

  if (prefixes.empty())
    return;

  std::string defaultPrefix = std::string(*prefixes.begin());
  for (auto it = prefixes.begin() + 1, end = prefixes.end(); it != end; it++) {
    if (it->empty())
      continue;
    std::string altSpelling =
        std::string(*it) + spelling.substr(defaultPrefix.size());
    fn(altSpelling, /*isAlternateSpelling=*/true);
  }
}

int makeOptions_main() {
  // Check if options were available.
  if (sizeof(rawOptions) == 0) {
    std::cerr << "error: swift/Options/Options.inc unavailable at compile time\n";
    return 1;
  }

  // Form the groups & record the ID mappings.
  unsigned rawOptionIdx = 0;
  for (const auto &rawOption : rawOptions) {
    if (rawOption.isGroup()) {
      std::string idName = rawOption.idName;
      auto groupSuffixStart = idName.rfind("Group");
      if (groupSuffixStart != std::string::npos) {
        idName.erase(idName.begin() + groupSuffixStart, idName.end());
        idName = swiftify(idName);
      }

      groupIndexByID[rawOption.id] = groups.size();
      groups.push_back({idName, rawOption.spelling, rawOption.helpText});
      ++rawOptionIdx;
      continue;
    }

    optionIndexByID[rawOption.id] = rawOptionIdx++;
  }

  // Add static properties to Option for each of the options.
  auto &out = std::cout;

  out <<
      "//===--------------- Options.swift - Swift Driver Options -----------------===//\n"
      "//\n"
      "// This source file is part of the Swift.org open source project\n"
      "//\n"
      "// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors\n"
      "// Licensed under Apache License v2.0 with Runtime Library Exception\n"
      "//\n"
      "// See https://swift.org/LICENSE.txt for license information\n"
      "// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors\n"
      "//\n"
      "//===----------------------------------------------------------------------===//\n"
      "//\n"
      "// NOTE: Generated file, do not edit!\n"
      "//\n"
      "// This file is generated from 'apple/swift:include/swift/Option/Options.td'.\n"
      "// Please see README.md#rebuilding-optionsswift for details\n"
      "//\n"
      "//===----------------------------------------------------------------------===//\n\n";
  out << "extension Option {\n";
  forEachOption([&](const RawOption &option) {
    // Look through each spelling of the option.
    forEachSpelling(option, [&](const std::string &spelling,
                                bool isAlternateSpelling) {
      out << "  public static let " << option.idName;

      // Add a '_' suffix if this is an alternate spelling.
      if (isAlternateSpelling)
        out << "_";

      // All options have Option type.
      out << ": Option = Option(\"" << spelling << "\"";

      out << ", ";
      switch (option.kind) {
      case OptionKind::Input:
        out << ".input";
        break;

      case OptionKind::CommaJoined:
        out << ".commaJoined";
        break;

      case OptionKind::Flag:
        out << ".flag";
        break;

      case OptionKind::Joined:
        out << ".joined";
        break;

      case OptionKind::JoinedOrSeparate:
        out << ".joinedOrSeparate";
        break;

      case OptionKind::RemainingArgs:
        out << ".remaining";
        break;

      case OptionKind::Separate:
        out << ".separate";
        break;

      case OptionKind::MultiArg:
        out << ".multiArg";
        break;

      case OptionKind::Group:
      case OptionKind::Unknown:
        assert(false && "Should have been filtered out");
      }

      if (option.isAlias()) {
        const auto &aliased = rawOptions[optionIndexByID[option.alias]];
        out << ", alias: Option." << aliased.idName;
      } else if (isAlternateSpelling) {
        out << ", alias: Option." << option.idName;
      }

      if (option.flags != 0 || option.kind == OptionKind::Input) {
        bool anyEmitted = false;
        auto emitFlag = [&](const char *name) {
          if (anyEmitted) {
            out << ", ";
          } else {
            anyEmitted = true;
          }

          out << name;
        };

        auto emitFlagIf = [&](SwiftFlags flag, const char *name) {
          if ((option.flags & flag) == 0) { return; }
          emitFlag(name);
        };

        out << ", attributes: [";
        emitFlagIf(HelpHidden, ".helpHidden");
        emitFlagIf(FrontendOption, ".frontend");
        emitFlagIf(NoDriverOption, ".noDriver");
        emitFlagIf(NoInteractiveOption, ".noInteractive");
        emitFlagIf(NoBatchOption, ".noBatch");
        emitFlagIf(DoesNotAffectIncrementalBuild, ".doesNotAffectIncrementalBuild");
        emitFlagIf(AutolinkExtractOption, ".autolinkExtract");
        emitFlagIf(ModuleWrapOption, ".moduleWrap");
        emitFlagIf(SwiftSynthesizeInterfaceOption, ".synthesizeInterface");
        if (option.kind == OptionKind::Input)
          emitFlag(".argumentIsPath");
        else
          emitFlagIf(ArgumentIsPath, ".argumentIsPath");
        emitFlagIf(ModuleInterfaceOption, ".moduleInterface");
        emitFlagIf(SupplementaryOutput, ".supplementaryOutput");
        emitFlagIf(ArgumentIsFileList, ".argumentIsFileList");
        emitFlagIf(CacheInvariant, ".cacheInvariant");
        out << "]";
      }

      if (option.metaVar) {
        out << ", metaVar: " << stringOrNil(option.metaVar);
      }
      if (option.helpText) {
        out << ", helpText: " << stringOrNilLeftTrimmed(option.helpText);
      }
      if (option.group != OptionID::Opt_INVALID) {
        out << ", group: ." << groups[groupIndexByID[option.group]].id;
      }
      if (option.kind == OptionKind::MultiArg) {
        out << ", numArgs: " << option.numArgs;
      }
      out << ")\n";
    });
  });
  out << "}\n";

  // Produce an "allOptions" property containing all of the known options.
  out << "\nextension Option {\n";
  out << "  public static var allOptions: [Option] {\n"
      << "    return [\n";
  forEachOption([&](const RawOption &option) {
      // Look through each spelling of the option.
      forEachSpelling(
          option, [&](const std::string &spelling, bool isAlternateSpelling) {
            out << "      Option." << option.idName;
            if (isAlternateSpelling)
              out << "_";
            out << ",\n";
          });
    });
  out << "    ]\n";
  out << "  }\n";
  out << "}\n";

  // Render the Option.Group type.
  out << "\nextension Option {\n";
  out << "  public enum Group {\n";
  for (const auto &group : groups) {
    out << "    case " << group.id << "\n";
  }
  out << "  }\n";
  out << "}\n";

  // Retrieve the display name of the group.
  out << "\n";
  out << "extension Option.Group {\n";
  out << "  public var name: String {\n";
  out << "    switch self {\n";
  for (const auto &group : groups) {
    out << "      case ." << group.id << ":\n";
    out << "        return \"" << group.name << "\"\n";
  }
  out << "    }\n";
  out << "  }\n";
  out << "}\n";

  // Retrieve the help text for the group.
  out << "\n";
  out << "extension Option.Group {\n";
  out << "  public var helpText: String? {\n";
  out << "    switch self {\n";
  for (const auto &group : groups) {
    out << "      case ." << group.id << ":\n";
    out << "        return " << stringOrNil(group.description) << "\n";
  }
  out << "    }\n";
  out << "  }\n";
  out << "}\n";


  return 0;
}
#else
static_assert(false, "Failed to locate/include llvm/Option/Option.h");
#endif
#else
static_assert(false, "Failed to locate/include llvm/Option/OptTable.h");
#endif
#else
#warning "Unable to include 'swift/Option/Options.inc', `makeOptions` will not be usable"
int makeOptions_main() {return 0;}
#endif
