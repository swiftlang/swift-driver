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
#include <sstream>
#include <vector>

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
};

//. The IDs of each option
enum class OptionID {
  Opt_INVALID = 0,
#define OPTION(PREFIX, NAME, ID, KIND, GROUP, ALIAS, ALIASARGS, FLAGS,  \
               PARAM, HELPTEXT, METAVAR, VALUES)                       \
  Opt_##ID,

#if __has_include("swift/Option/Options.inc")
#include "swift/Option/Options.inc"
#else
#warning "Unable to include 'swift/Option/Options.inc', `makeOptions` will not be usable"
#endif

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
  SwiftIndentOption = (1 << 11),
  ArgumentIsPath = (1 << 12),
  ModuleInterfaceOption = (1 << 13),
  SupplementaryOutput = (1 << 14),
  SwiftAPIExtractOption = (1 << 15),
  SwiftSymbolGraphExtractOption = (1 << 16),
};

struct Group {
  std::string id;
  const char *name;
  const char *description;
};

static std::vector<Group> groups;
static std::vector<OptionID> aliases;
static std::map<OptionID, unsigned> groupIndexByID;
static std::map<OptionID, unsigned> optionIndexByID;

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
  const char * const *prefixes;
  const char *spelling;
  std::string idName;
  OptionKind kind;
  OptionID group;
  OptionID alias;
  unsigned flags;
  const char *helpText;
  const char *metaVar;

  bool isGroup() const {
    return kind == OptionKind::Group;
  }

  bool isAlias() const {
    return alias != OptionID::Opt_INVALID;
  }

  bool isHidden() const {
    return flags & HelpHidden;
  }
  
  std::string wrapperName() const {
    switch (kind) {
    case OptionKind::Input:
      return "Argument";

    case OptionKind::CommaJoined:
    case OptionKind::Joined:
    case OptionKind::JoinedOrSeparate:
    case OptionKind::Separate:
      return "Option";

    case OptionKind::Flag:
      return "Flag";

    case OptionKind::RemainingArgs:
    case OptionKind::Group:
    case OptionKind::Unknown:
      assert(false && "Should have been filtered out");
    }
  }
  
  std::string initialValue() const {
    switch (kind) {
    case OptionKind::Input:
      return "[] as [String]";

    case OptionKind::CommaJoined:
    case OptionKind::Joined:
    case OptionKind::JoinedOrSeparate:
    case OptionKind::Separate:
      return "\"\"";

    case OptionKind::Flag:
      return "false";

    case OptionKind::RemainingArgs:
    case OptionKind::Group:
    case OptionKind::Unknown:
      assert(false && "Should have been filtered out");
    }
  }
};

#define PREFIX(NAME, VALUE) static const char *const NAME[] = VALUE;
#if __has_include("swift/Option/Options.inc")
#include "swift/Option/Options.inc"
#endif
#undef PREFIX

static const RawOption rawOptions[] = {
#define OPTION(PREFIX, NAME, ID, KIND, GROUP, ALIAS, ALIASARGS, FLAGS, PARAM,  \
               HELPTEXT, METAVAR, VALUES)                                      \
  { OptionID::Opt_##ID, PREFIX, NAME, swiftify(#ID), OptionKind::KIND, \
    OptionID::Opt_##GROUP, OptionID::Opt_##ALIAS, FLAGS, HELPTEXT, METAVAR },
#if __has_include("swift/Option/Options.inc")
#include "swift/Option/Options.inc"
#endif
#undef OPTION
};

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

void forEachGroup(std::function<void(const Group &)> fn) {
  for (const auto &group : groups) {
    fn(group);
  }
}

void forEachOptionInGroup(const Group group, std::function<void(const RawOption &)> fn) {
  forEachOption([&](const RawOption &option) {
    if (option.group == OptionID::Opt_INVALID)
      return;

    if (option.isAlias())
      return;
    
    auto optionGroup = groups[groupIndexByID[option.group]];
    if (group.id != optionGroup.id)
      return;

    fn(option);
  });
}

void forEachUngroupedOption(std::function<void(const RawOption &)> fn) {
  forEachOption([&](const RawOption &option) {
    if (option.kind == OptionKind::RemainingArgs)
      return;
    
    if (option.isAlias())
      return;
    
    if (option.group != OptionID::Opt_INVALID)
      return;
    
    fn(option);
  });
}

void forEachSpelling(const char * const *prefixes, const std::string &spelling,
                     std::function<void(const std::string &spelling,
                                        bool isAlternateSpelling)> fn) {
  if (!prefixes || !*prefixes) {
    fn(spelling, /*isAlternateSpelling=*/false);
    return;
  }

  bool isAlternateSpelling = false;
  while (*prefixes) {
    fn(*prefixes++ + spelling, isAlternateSpelling);
    isAlternateSpelling = true;
  }
}

std::string nameForSpelling(const std::string &spelling) {
  std::string optionName;
  bool singleDash = true;
  
  // Look for the "--" prefix
  if (spelling.rfind("--", 0) == 0) {
    optionName = spelling.substr(2);
  } else if (spelling[0] == '-') {
    optionName = spelling.substr(1);
  } else {
    return "";
  }
  
  if (optionName.length() == 1) {
    return ".customShort(\"" + optionName + "\", allowingJoined: true)";
  }
  
  if (singleDash) {
    return ".customLong(\"" + optionName + "\", withSingleDash: true)";
  } else {
    return ".customLong(\"" + optionName + "\")";
  }
}

std::string namesForOption(const RawOption option) {
  std::string names;
  
  auto spelling = std::string(option.spelling);
  if (spelling.back() == '=')
    spelling.pop_back();
  
  // Create a name for each spelling
  if (!option.prefixes || !*option.prefixes) {
    names = nameForSpelling(spelling);
  } else {
    auto prefixes = option.prefixes;
    while (*prefixes) {
      if (!names.empty()) names += ", ";
      names += nameForSpelling(*prefixes++ + spelling);
    }
  }
  
  // Look for aliases to this option
  for (const auto &aliasID : aliases) {
    auto aliasOption = rawOptions[optionIndexByID[aliasID]];
    if (aliasOption.alias != option.id)
      continue;
    
    names += ", ";
    names += namesForOption(aliasOption);
  }
  
  return names;
}

std::string declarationForOption(const RawOption option) {
  std::ostringstream result;
  
  result << "\n";
  result << "    @" << option.wrapperName();
  result << "(";
  if (option.kind != OptionKind::Input) {
    result << "name: [" << namesForOption(option) << "]";
  }
  result << ")\n";
  result << "    var " << std::string(option.idName) << " = " << option.initialValue();
  
  return result.str();
}

int makeOptions_main() {
  auto &out = std::cout;

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

    // Save aliases IDs for later, skipping over aliases that just exist
    // for equal sign-joined options.
    if (rawOption.alias != OptionID::Opt_INVALID) {
      if (std::string(rawOption.spelling).back() != '=') {
        aliases.push_back(rawOption.id);
      }
    }

    optionIndexByID[rawOption.id] = rawOptionIdx++;
  }
  
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
      "//===----------------------------------------------------------------------===//\n\n"
      "import ArgumentParser\n";
  
  forEachGroup([&](const Group &group) {
    out << "\n";
    out << "struct " << group.id << ": ParsableArguments {";
    forEachOptionInGroup(group, [&](const RawOption &option) {
      if ((option.flags & NoDriverOption) != 0)
        return;
      
      out << declarationForOption(option) << "\n";
    });
    out << "}\n";
  });
  
  out << "\nstruct General: ParsableArguments {";
  forEachUngroupedOption([&](const RawOption &option) {
    if ((option.flags & NoDriverOption) != 0)
      return;
    
    out << declarationForOption(option) << "\n";
  });
  out << "}\n\n";

  
  
  
  
  
  
  return 0;
  
  // old
  // ---------------------------------------------------------------------------
  
  
  
  
  // Add static properties to Option for each of the options.

  out << "extension Option {\n";
  forEachOption([&](const RawOption &option) {
    // Look through each spelling of the option.
    forEachSpelling(option.prefixes, option.spelling,
                    [&](const std::string &spelling,
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
        emitFlagIf(SwiftIndentOption, ".indent");
        if (option.kind == OptionKind::Input)
          emitFlag(".argumentIsPath");
        else
          emitFlagIf(ArgumentIsPath, ".argumentIsPath");
        emitFlagIf(ModuleInterfaceOption, ".moduleInterface");
        emitFlagIf(SupplementaryOutput, ".supplementaryOutput");
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
      forEachSpelling(option.prefixes, option.spelling,
                      [&](const std::string &spelling,
                          bool isAlternateSpelling) {
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
