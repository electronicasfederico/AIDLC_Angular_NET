# AIDLC Environment Setup — Angular + .NET

One-command setup for [AIDLC (AI-Driven Lifecycle)](https://github.com/awslabs/aidlc-workflows) workflows with **Angular** and **.NET** skills, targeting [OpenCode](https://opencode.ai) and/or [Claude Code](https://claude.ai).

The script downloads everything from official repositories and configures your project directory automatically — no manual cloning, no copy-pasting rules.

## What It Does

| Phase | Source | Description |
|-------|--------|-------------|
| **1. AIDLC Rules** | [awslabs/aidlc-workflows](https://github.com/awslabs/aidlc-workflows) | Installs the core AIDLC rule set (`.aidlc-rule-details/`) and creates `AGENTS.md` / `CLAUDE.md` from the core workflow |
| **2. Angular Skills** | [angular/skills](https://github.com/angular/skills) | Installs `angular-developer` and `angular-new-app` skills with component generation, signals, routing, and SSR guidance |
| **3. .NET Skills** | [dotnet/skills](https://github.com/dotnet/skills) | Installs 90+ .NET sub-skills covering ASP.NET Core, EF Core, testing, MSBuild, diagnostics, Blazor, MAUI, and more — with a router that dispatches to the right skill |
| **4. Integration** | *generated* | Creates `opencode.json` (commands), `.claude/settings.json`, framework extension rules, and updates `.gitignore` |

## Quick Start

```bash
# Clone this repo
git clone https://github.com/<your-user>/AIDLC_Angular_NET.git
cd AIDLC_Angular_NET

# Run against your project
chmod +x setup-aidlc-env.sh
./setup-aidlc-env.sh --target-dir /path/to/your/project
```

## Usage

```
./setup-aidlc-env.sh --target-dir DIR [OPTIONS]
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--target-dir DIR` | *(required)* | Target project directory to set up |
| `--agent AGENT` | `opencode` | Target agent: `opencode`, `claude`, or `both` |
| `--frameworks LIST` | `both` | Comma-separated: `angular`, `dotnet`, or `both` |
| `--force` | off | Overwrite existing files |
| `--skip-download` | off | Use a local source directory instead of downloading |
| `--source-dir DIR` | | Local source directory for `--skip-download` mode |
| `--aidlc-ref REF` | `main` | Git ref (branch/tag/commit) for AIDLC rules |
| `--angular-ref REF` | `main` | Git ref for Angular skills |
| `--dotnet-ref REF` | `main` | Git ref for .NET skills |

### Examples

```bash
# Full setup for OpenCode with both frameworks (default)
./setup-aidlc-env.sh --target-dir ./my-project

# Claude Code only, .NET only
./setup-aidlc-env.sh --target-dir ./my-api --agent claude --frameworks dotnet

# Both agents, Angular only, overwrite existing
./setup-aidlc-env.sh --target-dir ./my-app --agent both --frameworks angular --force

# Use local AIDLC source (offline mode)
./setup-aidlc-env.sh --target-dir ./my-project --skip-download --source-dir /path/to/aidlc-workflows

# Pin specific versions
./setup-aidlc-env.sh --target-dir ./my-project --aidlc-ref v1.2.0 --dotnet-ref v2.0.0
```

## Installed Structure

### OpenCode (`--agent opencode`)

```
your-project/
├── AGENTS.md                          # Core AIDLC workflow
├── opencode.json                      # Registered commands (/angular-developer, /dotnet-developer)
├── .aidlc-rule-details/
│   ├── ...                            # AIDLC rule files
│   └── extensions/
│       ├── angular/angular.md         # Angular framework bridge
│       └── dotnet/dotnet.md           # .NET framework bridge
└── .opencode/skills/
    ├── angular-skills/
    │   ├── angular-developer/         # Component/service/signal generation
    │   └── angular-new-app/           # Project scaffolding
    └── dotnet-skills/
        ├── dotnet-developer/SKILL.md  # Router skill (dispatches to sub-skills)
        ├── dotnet-aspnetcore/         # Web API, OpenTelemetry, file upload
        ├── dotnet-data/               # EF Core optimization
        ├── dotnet-test/               # 20+ testing skills (MSTest, xUnit, coverage)
        ├── dotnet-test-migration/     # Framework migration (MSTest v2→v4, xUnit→MSTest)
        ├── dotnet-msbuild/            # 17 MSBuild skills (diagnostics, perf, patterns)
        ├── dotnet-diag/               # Diagnostics, traces, dumps, benchmarks
        ├── dotnet-upgrade/            # .NET version migrations (8→9, 9→10, 10→11)
        ├── dotnet-blazor/             # Blazor components, forms, auth, prerendering
        ├── dotnet-maui/               # MAUI mobile/desktop (8 skills)
        ├── dotnet-ai/                 # AI/ML selection, MCP servers
        ├── dotnet-nuget/              # Central Package Management
        ├── dotnet-template-engine/    # Project template discovery & authoring
        ├── dotnet-advanced/           # P/Invoke, C# scripts, NuGet OIDC
        └── dotnet11/                  # .NET 11 new APIs
```

### Claude Code (`--agent claude`)

```
your-project/
├── CLAUDE.md                          # Core AIDLC workflow
├── .claude/
│   ├── settings.json                  # Permissions (Read, Edit, Write, git, dotnet, npm)
│   ├── rules/
│   │   ├── aidlc/                     # AIDLC rule files
│   │   ├── angular-extension.md       # Angular framework bridge
│   │   └── dotnet-extension.md        # .NET framework bridge
│   └── skills/
│       ├── angular-developer/         # Angular skills
│       ├── angular-new-app/           # Angular scaffolding
│       └── dotnet-developer/          # .NET router + all sub-skills
```

## .NET Skill Categories

The .NET skills are organized into **13 domains** with **90+ individual skills**:

| Domain | Skills | Topics |
|--------|--------|--------|
| ASP.NET Core | 3 | Web API endpoints, OpenTelemetry, file upload |
| EF Core | 1 | Query optimization, N+1 fixes |
| Testing | 20 | MSTest, xUnit, NUnit, coverage, anti-patterns, gap analysis, tagging |
| Test Migration | 5 | MSTest v1→v4, xUnit→MSTest, VSTest→MTP |
| MSBuild | 17 | Build perf, binlogs, parallelism, anti-patterns, modernization |
| Diagnostics | 7 | Traces, dumps, benchmarks, crash symbolication |
| Upgrades | 6 | .NET 8→9, 9→10, 10→11, AOT compat, nullable refs |
| Blazor | 9 | Components, forms, auth, prerendering, JS interop |
| MAUI | 8 | Lifecycle, navigation, data binding, theming |
| AI & MCP | 5 | Technology selection, MCP server creation/debug/testing/publish |
| Templates | 6 | Discovery, comparison, instantiation, authoring |
| Advanced | 3 | C# scripts, P/Invoke, NuGet OIDC |
| .NET 11 | 1 | System.Text.Json new APIs |

## .NET Router Skill

The setup includes a **router skill** (`dotnet-developer/SKILL.md`) that acts as an entry point for all .NET tasks. It lists every available sub-skill organized by domain so the agent can load the right one with the `skill` tool:

1. Identify the task domain (API, testing, build, diagnostics, etc.)
2. Load the specific sub-skill listed in the router
3. Follow the loaded skill's guidance

## AIDLC Workflow

This tool is part of the [AIDLC (AI-Driven Lifecycle)](https://github.com/awslabs/aidlc-workflows) ecosystem. The AIDLC workflow automates structured software development with AI agents through defined phases and rules.

Key AIDLC concepts:
- **Rule-based governance**: `.aidlc-rule-details/` contains structured rules that guide the agent
- **Phase state**: `aidlc-docs/aidlc-state.md` tracks the current workflow phase (created automatically on first run)
- **Audit trail**: All command executions are logged in `audit.md`
- **Framework extensions**: Bridge files connect AIDLC rules to framework-specific skills

## Based On

This project integrates skills and rules from these official repositories:

| Project | Repository | License | Description |
|---------|-----------|---------|-------------|
| **AIDLC** | [awslabs/aidlc-workflows](https://github.com/awslabs/aidlc-workflows) | [Apache-2.0](https://github.com/awslabs/aidlc-workflows/blob/main/LICENSE) | AI-Driven Lifecycle workflow rules and governance framework |
| **Angular Skills** | [angular/skills](https://github.com/angular/skills) | [MIT](https://github.com/angular/skills/blob/main/LICENSE) | Official Angular development skills for AI agents |
| **.NET Skills** | [dotnet/skills](https://github.com/dotnet/skills) | [MIT](https://github.com/dotnet/skills/blob/main/LICENSE) | Official .NET development skills for AI agents (Microsoft) |
| **OpenCode** | [opencode.ai](https://opencode.ai) | [MIT](https://github.com/anomalyco/opencode/blob/main/LICENSE) | AI-powered coding assistant with skill system |
| **Claude Code** | [Anthropic](https://claude.ai) | Proprietary | AI coding assistant by Anthropic |

## Requirements

- `bash` 4.0+
- `curl`
- `tar`
- Internet connection (for downloading from GitHub, or use `--skip-download` for offline mode)

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

> **Note**: The skills and rules downloaded by this script are subject to the licenses of their respective upstream repositories (see [Based On](#based-on)).
