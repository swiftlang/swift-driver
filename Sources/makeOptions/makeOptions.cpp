#include <cassert>
#include <functional>
#include <iostream>
#include <map>
#include <set>
#include <string>
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
};

/// Raw option from the TableGen'd output of the Swift options.
struct RawOption {
  OptionID id;
  const char * const *prefixes;
  const char *spelling;
  const char *idName;
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
};

#define PREFIX(NAME, VALUE) static const char *const NAME[] = VALUE;
#if __has_include("swift/Option/Options.inc")
#include "swift/Option/Options.inc"
#endif
#undef PREFIX

static const RawOption rawOptions[] = {
#define OPTION(PREFIX, NAME, ID, KIND, GROUP, ALIAS, ALIASARGS, FLAGS, PARAM,  \
               HELPTEXT, METAVAR, VALUES)                                      \
  { OptionID::Opt_##ID, PREFIX, NAME, #ID, OptionKind::KIND, \
    OptionID::Opt_##GROUP, OptionID::Opt_##ALIAS, FLAGS, HELPTEXT, METAVAR },
#if __has_include("swift/Option/Options.inc")
#include "swift/Option/Options.inc"
#endif
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

static std::set<std::string> swiftKeywords = { "internal", "static" };

static std::string escapeKeyword(const std::string &name) {
  if (swiftKeywords.count(name) > 0)
    return "`" + name + "`";

  return name;
}

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

    if (rawOption.kind == OptionKind::Input)
      continue;

    fn(rawOption);
  }
}

void forEachSpelling(const char * const *prefixes, const std::string &spelling,
                     std::function<void(const std::string &spelling,
                                        bool isAlternateSpelling)> fn) {
  bool isAlternateSpelling = false;
  while (*prefixes) {
    fn(*prefixes++ + spelling, isAlternateSpelling);
    isAlternateSpelling = true;
  }
}

enum class OptionTableKind {
  Interactive,
  Batch,
  Frontend,
  ModuleWrap,
  AutolinkExtract,
  Indent,
};

static const char *optionTableKindName(OptionTableKind kind) {
  switch (kind) {
  case OptionTableKind::Interactive:
    return "interactive";

  case OptionTableKind::Batch:
    return "batch";

  case OptionTableKind::Frontend:
    return "frontend";

  case OptionTableKind::ModuleWrap:
    return "moduleWrap";

  case OptionTableKind::AutolinkExtract:
    return "autolinkExtract";

  case OptionTableKind::Indent:
    return "indent";
  }
}

static bool optionTableIncludes(OptionTableKind kind, const RawOption &option) {
  assert(!option.isGroup());
  
  switch (kind) {
  case OptionTableKind::Interactive:
    return !(option.flags & (NoDriverOption | NoInteractiveOption));

  case OptionTableKind::Batch:
    return !(option.flags & (NoDriverOption | NoBatchOption));
    
  case OptionTableKind::Frontend:
    return option.flags & FrontendOption;

  case OptionTableKind::ModuleWrap:
    return option.flags & ModuleWrapOption;

  case OptionTableKind::AutolinkExtract:
    return option.flags & AutolinkExtractOption;

  case OptionTableKind::Indent:
    return option.flags & SwiftIndentOption;
  }  
}

std::string makeGenerator(const RawOption &option) {
  std::string idName = option.idName;
  if (option.isAlias()) {
    idName = rawOptions[optionIndexByID[option.alias]].idName;
  } else {
    idName = option.idName;
  }
  
  auto makeWithArg = [&](const std::string &caseName) {
    return "Generator." + caseName + " { Option." + idName + "($0) }";
  };
  
  switch (option.kind) {
  case OptionKind::Group:
  case OptionKind::Unknown:
    assert(false);

  case OptionKind::Input:
    return "Generator.input";

  case OptionKind::Flag:
    return "Generator.flag { Option." + idName + " }";

  case OptionKind::Joined:
    return makeWithArg("joined");
    
  case OptionKind::Separate:
    return makeWithArg("separate");

  case OptionKind::RemainingArgs:
    return makeWithArg("remaining");

  case OptionKind::CommaJoined:
    return makeWithArg("commaJoined");

  case OptionKind::JoinedOrSeparate:
    return makeWithArg("joinedOrSeparate");
  }
}

void printOptionTable(std::ostream &out, OptionTableKind kind) {
  out << "\n";
  out << "extension OptionTable {\n";
  out << "  public static var " << optionTableKindName(kind) << "Options"
      << ": OptionTable {\n";
  out << "    var parser = OptionTable()\n";

  forEachOption([&](const RawOption &option) {
      if (!optionTableIncludes(kind, option))
        return;

      forEachSpelling(option.prefixes, option.spelling,
                      [&](const std::string &spelling,
                          bool isAlternateSpelling) {
          if (option.isAlias() || isAlternateSpelling) {
            out << "      parser.addAlias(spelling: \"" << spelling << "\", "
                << "generator: " << makeGenerator(option) << ", "
                << "isHidden: " << (option.isHidden() ? "true" : "false")
                << ")\n";
            return;
          }

          out << "      parser.addOption(spelling: \"" << spelling << "\", "
              << "generator: " << makeGenerator(option) << ", "
              << "isHidden: " << (option.isHidden() ? "true" : "false") << ", "
              << "metaVar: " << stringOrNil(option.metaVar) << ", "
              << "helpText: " << stringOrNilLeftTrimmed(option.helpText)
              << ")\n";
        });
    });

  out << "    return parser\n";
  out << "  }\n";
  out << "}\n";
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
      auto groupSuffixStart = idName.rfind("_Group");
      if (groupSuffixStart != std::string::npos) {
        idName.erase(idName.begin() + groupSuffixStart, idName.end());
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
  out << "\n";
  out << "extension Option {\n";
  forEachOption([&](const RawOption &option) {
    // Look through each spelling of the option.
    forEachSpelling(option.prefixes, option.spelling,
                    [&](const std::string &spelling,
                        bool isAlternateSpelling) {
      out << "  @Option(\"" << spelling << "\"";

      out << ", ";
      switch (option.kind) {
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
      case OptionKind::Input:
      case OptionKind::Unknown:
        assert(false && "Should have been filtered out");
      }

      if (option.isAlias()) {
        const auto &aliased = rawOptions[optionIndexByID[option.alias]];
        out << ", alias: Option." << aliased.idName;
      } else if (isAlternateSpelling) {
        out << ", alias: Option." << option.idName;
      }

      if (option.flags != 0) {
        bool anyEmitted = false;
        auto emitFlag = [&](SwiftFlags flag, const char *name) {
          if ((option.flags & flag) == 0) { return; }

          if (anyEmitted) {
            out << ", ";
          } else {
            anyEmitted = true;
          }

          out << name;
        };

        out << ", attributes: [";
        emitFlag(HelpHidden, ".helpHidden");
        emitFlag(FrontendOption, ".frontend");
        emitFlag(NoDriverOption, ".noDriver");
        emitFlag(NoInteractiveOption, ".noInteractive");
        emitFlag(NoBatchOption, ".noBatch");
        emitFlag(DoesNotAffectIncrementalBuild, ".doesNotAffectIncrementalBuild");
        emitFlag(AutolinkExtractOption, ".autolinkExtract");
        emitFlag(ModuleWrapOption, ".moduleWrap");
        emitFlag(SwiftIndentOption, ".indent");
        emitFlag(ArgumentIsPath, ".argumentIsPath");
        emitFlag(ModuleInterfaceOption, ".moduleInterface");
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
      out << ") static var ";

      // Add a '_' suffix if this is an alternate spelling.
      if (isAlternateSpelling)
        out << option.idName << "_";
      else
        out << escapeKeyword(option.idName);

      // All options have Option type.
      out << ": Option\n";
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
        out << "      Option._" << option.idName;
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
    out << "    case " << escapeKeyword(group.id) << "\n";
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
