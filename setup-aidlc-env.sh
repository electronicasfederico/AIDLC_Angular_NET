#!/usr/bin/env bash
# =============================================================================
# AIDLC Environment Setup Script (Standalone)
# =============================================================================
# Downloads everything from official repos and sets up the complete AIDLC
# environment with Angular + .NET skills for OpenCode and/or Claude Code.
#
# Official Sources:
#   - AIDLC Rules:  https://github.com/awslabs/aidlc-workflows
#   - Angular Skills: https://github.com/angular/skills
#   - .NET Skills:   https://github.com/dotnet/skills
#
# Usage:
#   ./setup-aidlc-env.sh --target-dir /path/to/project [OPTIONS]
#
# Options:
#   --target-dir DIR      Target project directory (required)
#   --agent AGENT         Target agent: opencode, claude, or both (default: opencode)
#   --frameworks LIST     Comma-separated: angular,dotnet,both (default: both)
#   --force               Overwrite existing files
#   --skip-download       Use local source dir instead of downloading
#   --source-dir DIR      Local source for --skip-download mode
#   --aidlc-ref REF       Git ref for AIDLC (default: main)
#   --angular-ref REF     Git ref for Angular skills (default: main)
#   --dotnet-ref REF      Git ref for .NET skills (default: main)
#   --help                Show this help
# =============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
TARGET_DIR=""
AGENT="opencode"
FRAMEWORKS="both"
FORCE=false
SKIP_DOWNLOAD=false
SOURCE_DIR=""
AIDLC_REF="main"
ANGULAR_REF="main"
DOTNET_REF="main"
CACHE_DIR=""

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header()  { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ── Parse Args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-dir)      TARGET_DIR="$2"; shift 2 ;;
        --agent)           AGENT="$2"; shift 2 ;;
        --frameworks)      FRAMEWORKS="$2"; shift 2 ;;
        --force)           FORCE=true; shift ;;
        --skip-download)   SKIP_DOWNLOAD=true; shift ;;
        --source-dir)      SOURCE_DIR="$2"; shift 2 ;;
        --aidlc-ref)       AIDLC_REF="$2"; shift 2 ;;
        --angular-ref)     ANGULAR_REF="$2"; shift 2 ;;
        --dotnet-ref)      DOTNET_REF="$2"; shift 2 ;;
        --help)
            sed -n '2,/^# ====/p' "$0" | head -n -1
            exit 0
            ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$TARGET_DIR" ]]; then
    error "Usage: $0 --target-dir <path> [--agent opencode|claude|both] [--frameworks angular|dotnet|both]"
    exit 1
fi

if [[ "$AGENT" != "opencode" && "$AGENT" != "claude" && "$AGENT" != "both" ]]; then
    error "Invalid --agent value: $AGENT (must be opencode, claude, or both)"
    exit 1
fi

HAS_OPENCODE=false
HAS_CLAUDE=false
[[ "$AGENT" == "opencode" || "$AGENT" == "both" ]] && HAS_OPENCODE=true
[[ "$AGENT" == "claude" || "$AGENT" == "both" ]] && HAS_CLAUDE=true

# ── Validate Dependencies ─────────────────────────────────────────────────────
for cmd in curl tar; do
    if ! command -v "$cmd" &>/dev/null; then
        error "Required command not found: $cmd"
        exit 1
    fi
done

# ── Prepare ───────────────────────────────────────────────────────────────────
mkdir -p "$TARGET_DIR" 2>/dev/null || true
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$CACHE_DIR"' EXIT

HAS_ANGULAR=false
HAS_DOTNET=false
[[ "$FRAMEWORKS" == "angular" || "$FRAMEWORKS" == "both" ]] && HAS_ANGULAR=true
[[ "$FRAMEWORKS" == "dotnet" || "$FRAMEWORKS" == "both" ]] && HAS_DOTNET=true

echo ""
echo "============================================"
echo "  AIDLC Environment Setup (Standalone)"
echo "============================================"
info "Target:      $TARGET_DIR"
info "Agent:       $AGENT"
info "Frameworks:  $FRAMEWORKS"
info "Download:    $([ "$SKIP_DOWNLOAD" == "true" ] && echo "no (local)" || echo "yes (official repos)")"
echo ""

# =============================================================================
# PHASE 1: Download AIDLC Rules from Official Repo
# =============================================================================
header "Phase 1: AIDLC Rules (awslabs/aidlc-workflows)"

AIDLC_TARGET="$TARGET_DIR/.aidlc-rule-details"
if [[ -d "$AIDLC_TARGET" && "$FORCE" != "true" ]]; then
    warn ".aidlc-rule-details/ already exists (use --force to overwrite)"
else
    if [[ "$SKIP_DOWNLOAD" == "true" ]]; then
        if [[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR/.aidlc-rule-details" ]]; then
            cp -r "$SOURCE_DIR/.aidlc-rule-details" "$AIDLC_TARGET"
            count=$(find "$AIDLC_TARGET" -name "*.md" | wc -l)
            success "Copied $count AIDLC rule files from local source"
        else
            warn "No local .aidlc-rule-details found, skipping"
        fi
    else
        info "Downloading AIDLC rules (ref: $AIDLC_REF)..."
        AIDLC_URL="https://github.com/awslabs/aidlc-workflows/archive/refs/heads/${AIDLC_REF}.tar.gz"
        AIDLC_TAR="$CACHE_DIR/aidlc.tar.gz"

        if curl -sL -o "$AIDLC_TAR" "$AIDLC_URL" 2>/dev/null; then
            # Extract and find aws-aidlc-rule-details
            tar -xzf "$AIDLC_TAR" -C "$CACHE_DIR/" 2>/dev/null
            AIDLC_EXTRACTED=$(find "$CACHE_DIR" -maxdepth 1 -type d -name "aidlc-workflows-*" | head -1)

            if [[ -n "$AIDLC_EXTRACTED" && -d "$AIDLC_EXTRACTED/aidlc-rules" ]]; then
                # Try to find aws-aidlc-rule-details (official structure)
                if [[ -d "$AIDLC_EXTRACTED/aidlc-rules/aws-aidlc-rule-details" ]]; then
                    cp -r "$AIDLC_EXTRACTED/aidlc-rules/aws-aidlc-rule-details" "$AIDLC_TARGET"
                elif [[ -d "$AIDLC_EXTRACTED/.aidlc-rule-details" ]]; then
                    # Alternative structure
                    cp -r "$AIDLC_EXTRACTED/.aidlc-rule-details" "$AIDLC_TARGET"
                else
                    # Fallback: look for any rule-details directory
                    FOUND=$(find "$AIDLC_EXTRACTED" -type d -name "*aidlc-rule-details" | head -1)
                    if [[ -n "$FOUND" ]]; then
                        cp -r "$FOUND" "$AIDLC_TARGET"
                    else
                        error "Could not find aidlc-rule-details in downloaded repo"
                        exit 1
                    fi
                fi
                count=$(find "$AIDLC_TARGET" -name "*.md" | wc -l)
                success "Downloaded and extracted $count AIDLC rule files"
            else
                error "Invalid AIDLC repo structure"
                exit 1
            fi
        else
            error "Failed to download AIDLC rules from $AIDLC_URL"
            exit 1
        fi
    fi
fi

# Also set up AGENTS.md / CLAUDE.md from AIDLC core workflow
AGENTS_FILE="$TARGET_DIR/AGENTS.md"
CLAUDE_FILE="$TARGET_DIR/CLAUDE.md"

# Find the core workflow source file
CORE_WORKFLOW=""
if [[ "$SKIP_DOWNLOAD" == "true" ]]; then
    if [[ -n "$SOURCE_DIR" && -f "$SOURCE_DIR/AGENTS.md" ]]; then
        CORE_WORKFLOW="$SOURCE_DIR/AGENTS.md"
    fi
else
    AIDLC_EXTRACTED=$(find "$CACHE_DIR" -maxdepth 1 -type d -name "aidlc-workflows-*" | head -1)
    if [[ -n "$AIDLC_EXTRACTED" ]]; then
        if [[ -f "$AIDLC_EXTRACTED/aidlc-rules/aws-aidlc-rules/core-workflow.md" ]]; then
            CORE_WORKFLOW="$AIDLC_EXTRACTED/aidlc-rules/aws-aidlc-rules/core-workflow.md"
        elif [[ -f "$AIDLC_EXTRACTED/AGENTS.md" ]]; then
            CORE_WORKFLOW="$AIDLC_EXTRACTED/AGENTS.md"
        fi
    fi
fi

# Create AGENTS.md for OpenCode
if [[ "$HAS_OPENCODE" == "true" && -n "$CORE_WORKFLOW" ]]; then
    if [[ ! -f "$AGENTS_FILE" || "$FORCE" == "true" ]]; then
        cp "$CORE_WORKFLOW" "$AGENTS_FILE"
        success "Copied AGENTS.md from AIDLC core workflow"
    fi
fi

# Create CLAUDE.md for Claude Code
if [[ "$HAS_CLAUDE" == "true" && -n "$CORE_WORKFLOW" ]]; then
    if [[ ! -f "$CLAUDE_FILE" || "$FORCE" == "true" ]]; then
        cp "$CORE_WORKFLOW" "$CLAUDE_FILE"
        success "Copied CLAUDE.md from AIDLC core workflow"
    fi
    # Also copy AIDLC rules into .claude/rules/aidlc/ for Claude's rules engine
    CLAUDE_RULES_DIR="$TARGET_DIR/.claude/rules/aidlc"
    if [[ ! -d "$CLAUDE_RULES_DIR" || "$FORCE" == "true" ]]; then
        if [[ -d "$AIDLC_TARGET" ]]; then
            mkdir -p "$CLAUDE_RULES_DIR"
            cp -r "$AIDLC_TARGET"/* "$CLAUDE_RULES_DIR/"
            count=$(find "$CLAUDE_RULES_DIR" -name "*.md" | wc -l)
            success "Copied $count AIDLC rules to .claude/rules/aidlc/"
        fi
    fi
fi

# ── Helper: Create .NET router SKILL.md ──────────────────────────────────────
create_dotnet_router() {
    local dest="$1"
    cat > "$dest" << 'ENDROUTER'
# .NET Developer Skill

Backend development for .NET projects. This skill routes to the specific
sub-skill needed for each task domain.

## When to Use
- Building or modifying Web APIs, controllers, minimal APIs
- Working with Entity Framework Core (migrations, queries, configurations)
- Writing or running .NET tests (MSTest, xUnit, NUnit)
- Diagnosing .NET performance, dumps, traces
- MSBuild configuration and optimization

## Skill Categories

### Web API & ASP.NET Core
- `dotnet-aspnetcore/dotnet-webapi` — Web API endpoints, HTTP semantics, OpenAPI
- `dotnet-aspnetcore/configuring-opentelemetry-dotnet` — OpenTelemetry setup
- `dotnet-aspnetcore/minimal-api-file-upload` — File upload endpoints

### Data Access (EF Core)
- `dotnet-data/optimizing-ef-core-queries` — Query optimization, N+1 fixes

### Testing
- `dotnet-test/writing-mstest-tests` — Write MSTest unit tests
- `dotnet-test/run-tests` — Run tests with dotnet test
- `dotnet-test/code-testing-agent` — Generate comprehensive test suites
- `dotnet-test/test-anti-patterns` — Audit tests for quality issues
- `dotnet-test/coverage-analysis` — Code coverage analysis
- `dotnet-test/assertion-quality` — Assertion diversity analysis
- `dotnet-test/test-gap-analysis` — Find untested edge cases
- `dotnet-test/test-tagging` — Categorize tests with traits
- `dotnet-test/test-smell-detection` — Academic smell catalog
- `dotnet-test/grade-tests` — Grade test methods
- `dotnet-test/crap-score` — Change risk anti-patterns
- `dotnet-test/detect-static-dependencies` — Find untestable statics
- `dotnet-test/generate-testability-wrappers` — Create DI wrappers
- `dotnet-test/migrate-static-to-wrapper` — Migrate statics to injectable
- `dotnet-test/find-untested-sources` — Find untested files
- `dotnet-test/filter-syntax` — Test filter reference
- `dotnet-test/code-testing-extensions` — Language-specific extensions
- `dotnet-test/platform-detection` — Detect test platform/framework
- `dotnet-test/test-analysis-extensions` — Analysis lookup tables
- `dotnet-test/mtp-hot-reload` — MTP hot reload

### Test Migration
- `dotnet-test-migration/migrate-mstest-v1v2-to-v3` — MSTest v1/v2 → v3
- `dotnet-test-migration/migrate-mstest-v3-to-v4` — MSTest v3 → v4
- `dotnet-test-migration/migrate-xunit-to-mstest` — xUnit → MSTest
- `dotnet-test-migration/migrate-xunit-to-xunit-v3` — xUnit v2 → v3
- `dotnet-test-migration/migrate-vstest-to-mtp` — VSTest → Microsoft.Testing.Platform

### Build & MSBuild
- `dotnet-msbuild/build-perf-diagnostics` — Diagnose slow builds
- `dotnet-msbuild/build-perf-baseline` — Establish performance baselines
- `dotnet-msbuild/build-parallelism` — Optimize parallel builds
- `dotnet-msbuild/incremental-build` — Fix incremental build issues
- `dotnet-msbuild/msbuild-antipatterns` — Catalog of anti-patterns
- `dotnet-msbuild/msbuild-modernization` — Modernize to SDK-style
- `dotnet-msbuild/directory-build-organization` — Directory.Build.props/targets
- `dotnet-msbuild/target-authoring` — Custom MSBuild targets
- `dotnet-msbuild/property-patterns` — Property definition patterns
- `dotnet-msbuild/item-management` — Item group management
- `dotnet-msbuild/extension-points` — MSBuild extensibility
- `dotnet-msbuild/eval-performance` — Project evaluation performance
- `dotnet-msbuild/binlog-failure-analysis` — Analyze build failures
- `dotnet-msbuild/binlog-generation` — Generate binary logs
- `dotnet-msbuild/check-bin-obj-clash` — Detect output conflicts
- `dotnet-msbuild/including-generated-files` — Include build-generated files
- `dotnet-msbuild/msbuild-server` — MSBuild Server for CLI
- `dotnet-msbuild/resolve-project-references` — Reference resolution timing

### Diagnostics & Performance
- `dotnet-diag/analyzing-dotnet-performance` — Performance anti-patterns
- `dotnet-diag/dotnet-trace-collect` — Capture diagnostic traces
- `dotnet-diag/dump-collect` — Collect crash dumps
- `dotnet-diag/microbenchmarking` — BenchmarkDotNet benchmarks
- `dotnet-diag/android-tombstone-symbolication` — Android crash symbolication
- `dotnet-diag/apple-crash-symbolication` — Apple crash symbolication
- `dotnet-diag/clr-activation-debugging` — CLR activation issues

### Upgrades & Migration
- `dotnet-upgrade/migrate-dotnet8-to-dotnet9` — .NET 8 → 9
- `dotnet-upgrade/migrate-dotnet9-to-dotnet10` — .NET 9 → 10
- `dotnet-upgrade/migrate-dotnet10-to-dotnet11` — .NET 10 → 11
- `dotnet-upgrade/dotnet-aot-compat` — AOT/trimming compatibility
- `dotnet-upgrade/migrate-nullable-references` — Enable nullable references
- `dotnet-upgrade/thread-abort-migration` — Thread.Abort → cancellation

### NuGet & Packaging
- `dotnet-nuget/convert-to-cpm` — Central Package Management

### AI & MCP
- `dotnet-ai/technology-selection` — AI/ML technology selection
- `dotnet-ai/mcp-csharp-create` — Create MCP servers
- `dotnet-ai/mcp-csharp-debug` — Debug MCP servers
- `dotnet-ai/mcp-csharp-test` — Test MCP servers
- `dotnet-ai/mcp-csharp-publish` — Publish MCP servers

### Advanced C#
- `dotnet-advanced/csharp-scripts` — File-based C# apps
- `dotnet-advanced/dotnet-pinvoke` — P/Invoke native interop
- `dotnet-advanced/nuget-trusted-publishing` — NuGet OIDC publishing

### Templates
- `dotnet-template-engine/template-discovery` — Find project templates
- `dotnet-template-engine/template-comparison` — Compare templates
- `dotnet-template-engine/template-instantiation` — Create from templates
- `dotnet-template-engine/template-authoring` — Create custom templates
- `dotnet-template-engine/template-validation` — Validate templates
- `dotnet-template-engine/template-smart-defaults` — Cross-parameter defaults

### .NET MAUI (Mobile/Desktop)
- `dotnet-maui/dotnet-maui-doctor` — Diagnose MAUI environment
- `dotnet-maui/maui-app-lifecycle` — App lifecycle events
- `dotnet-maui/maui-collectionview` — CollectionView guidance
- `dotnet-maui/maui-data-binding` — XAML/C# data binding
- `dotnet-maui/maui-dependency-injection` — DI configuration
- `dotnet-maui/maui-safe-area` — Safe area/edge-to-edge layout
- `dotnet-maui/maui-shell-navigation` — Shell navigation
- `dotnet-maui/maui-theming` — Light/dark mode theming

### Blazor (Web UI)
- `dotnet-blazor/create-blazor-project` — Create new Blazor app
- `dotnet-blazor/author-component` — Write Blazor components
- `dotnet-blazor/collect-user-input` — Forms and validation
- `dotnet-blazor/fetch-and-send-data` — HTTP data fetching
- `dotnet-blazor/use-js-interop` — JavaScript interop
- `dotnet-blazor/coordinate-components` — Share state between components
- `dotnet-blazor/configure-auth` — Authentication/authorization
- `dotnet-blazor/plan-ui-change` — Plan complex UI features
- `dotnet-blazor/support-prerendering` — Prerendering support

### Experimental
- `dotnet-experimental/exp-mock-usage-analysis` — Audit mock usage
- `dotnet-experimental/exp-simd-vectorization` — SIMD optimization
- `dotnet-experimental/exp-test-maintainability` — Test maintainability

### .NET 11
- `dotnet11/system-text-json-net11` — STJ new APIs

## Usage
1. Identify the task domain (API, testing, build, diagnostics, etc.)
2. Use the `skill` tool to load the specific sub-skill listed above
3. Follow the loaded skill's guidance for the task
ENDROUTER
}

# =============================================================================
# PHASE 2: Download Angular Skills from Official Repo
# =============================================================================
if [[ "$HAS_ANGULAR" == "true" ]]; then
    header "Phase 2: Angular Skills (angular/skills)"

    # Download Angular skills to cache (once)
    ANGULAR_EXTRACTED=""
    if [[ "$SKIP_DOWNLOAD" != "true" ]]; then
        info "Downloading Angular skills (ref: $ANGULAR_REF)..."
        ANGULAR_URL="https://github.com/angular/skills/archive/refs/heads/${ANGULAR_REF}.tar.gz"
        ANGULAR_TAR="$CACHE_DIR/angular-skills.tar.gz"
        ANGULAR_EXTRACT_DIR="$CACHE_DIR/angular-extract"
        mkdir -p "$ANGULAR_EXTRACT_DIR"

        if curl -sL -o "$ANGULAR_TAR" "$ANGULAR_URL" 2>/dev/null; then
            tar -xzf "$ANGULAR_TAR" -C "$ANGULAR_EXTRACT_DIR" 2>/dev/null
            ANGULAR_EXTRACTED=$(find "$ANGULAR_EXTRACT_DIR" -maxdepth 1 -type d -name "skills-*" | head -1)
            if [[ -z "$ANGULAR_EXTRACTED" ]]; then
                error "Failed to extract Angular skills"
            fi
        else
            error "Failed to download Angular skills from $ANGULAR_URL"
        fi
    fi

    # ── OpenCode: .opencode/skills/angular-skills/ ──
    if [[ "$HAS_OPENCODE" == "true" ]]; then
        ANGULAR_SKILLS_TARGET="$TARGET_DIR/.opencode/skills/angular-skills"
        if [[ -d "$ANGULAR_SKILLS_TARGET" && "$FORCE" != "true" ]]; then
            warn "OpenCode Angular skills already exist (use --force to overwrite)"
        else
            if [[ "$SKIP_DOWNLOAD" == "true" ]]; then
                if [[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR/.opencode/skills/angular-skills" ]]; then
                    mkdir -p "$TARGET_DIR/.opencode/skills"
                    cp -r "$SOURCE_DIR/.opencode/skills/angular-skills" "$ANGULAR_SKILLS_TARGET"
                    count=$(find "$ANGULAR_SKILLS_TARGET" -type f | wc -l)
                    success "Copied Angular skills to OpenCode ($count files)"
                fi
            elif [[ -n "$ANGULAR_EXTRACTED" ]]; then
                mkdir -p "$ANGULAR_SKILLS_TARGET"
                if [[ -d "$ANGULAR_EXTRACTED/angular-developer" ]]; then
                    cp -r "$ANGULAR_EXTRACTED/angular-developer" "$ANGULAR_SKILLS_TARGET/"
                fi
                if [[ -d "$ANGULAR_EXTRACTED/angular-new-app" ]]; then
                    cp -r "$ANGULAR_EXTRACTED/angular-new-app" "$ANGULAR_SKILLS_TARGET/"
                fi
                count=$(find "$ANGULAR_SKILLS_TARGET" -type f 2>/dev/null | wc -l)
                [[ $count -gt 0 ]] && success "Copied Angular skills to OpenCode ($count files)"
            fi
        fi
    fi

    # ── Claude: .claude/skills/angular-developer/ + angular-new-app/ ──
    if [[ "$HAS_CLAUDE" == "true" ]]; then
        CLAUDE_ANG_DEV="$TARGET_DIR/.claude/skills/angular-developer"
        CLAUDE_ANG_NEW="$TARGET_DIR/.claude/skills/angular-new-app"
        if [[ (-d "$CLAUDE_ANG_DEV" && -d "$CLAUDE_ANG_NEW") && "$FORCE" != "true" ]]; then
            warn "Claude Angular skills already exist (use --force to overwrite)"
        else
            if [[ "$SKIP_DOWNLOAD" == "true" ]]; then
                if [[ -n "$SOURCE_DIR" ]]; then
                    [[ -d "$SOURCE_DIR/.claude/skills/angular-developer" ]] && \
                        cp -r "$SOURCE_DIR/.claude/skills/angular-developer" "$CLAUDE_ANG_DEV"
                    [[ -d "$SOURCE_DIR/.claude/skills/angular-new-app" ]] && \
                        cp -r "$SOURCE_DIR/.claude/skills/angular-new-app" "$CLAUDE_ANG_NEW"
                    success "Copied Angular skills to Claude from local source"
                fi
            elif [[ -n "$ANGULAR_EXTRACTED" ]]; then
                if [[ -d "$ANGULAR_EXTRACTED/angular-developer" ]]; then
                    mkdir -p "$CLAUDE_ANG_DEV"
                    cp -r "$ANGULAR_EXTRACTED/angular-developer/"* "$CLAUDE_ANG_DEV/"
                fi
                if [[ -d "$ANGULAR_EXTRACTED/angular-new-app" ]]; then
                    mkdir -p "$CLAUDE_ANG_NEW"
                    cp -r "$ANGULAR_EXTRACTED/angular-new-app/"* "$CLAUDE_ANG_NEW/"
                fi
                count=$(find "$TARGET_DIR/.claude/skills/angular-"* -type f 2>/dev/null | wc -l)
                [[ $count -gt 0 ]] && success "Copied Angular skills to Claude ($count files)"
            fi
        fi
    fi
fi

# =============================================================================
# PHASE 3: Download .NET Skills from Official Repo
# =============================================================================
if [[ "$HAS_DOTNET" == "true" ]]; then
    header "Phase 3: .NET Skills (dotnet/skills)"

    # Download .NET skills to cache (once)
    DOTNET_EXTRACTED=""
    if [[ "$SKIP_DOWNLOAD" != "true" ]]; then
        info "Downloading .NET skills (ref: $DOTNET_REF)..."
        DOTNET_URL="https://github.com/dotnet/skills/archive/refs/heads/${DOTNET_REF}.tar.gz"
        DOTNET_TAR="$CACHE_DIR/dotnet-skills.tar.gz"
        DOTNET_EXTRACT_DIR="$CACHE_DIR/dotnet-extract"
        mkdir -p "$DOTNET_EXTRACT_DIR"

        if curl -sL -o "$DOTNET_TAR" "$DOTNET_URL" 2>/dev/null; then
            tar -xzf "$DOTNET_TAR" -C "$DOTNET_EXTRACT_DIR" 2>/dev/null
            DOTNET_EXTRACTED=$(find "$DOTNET_EXTRACT_DIR" -maxdepth 1 -type d -name "skills-*" | head -1)
            if [[ -z "$DOTNET_EXTRACTED" ]]; then
                error "Failed to extract .NET skills"
            fi
        else
            error "Failed to download .NET skills from $DOTNET_URL"
        fi
    fi

    # ── OpenCode: .opencode/skills/dotnet-skills/ ──
    if [[ "$HAS_OPENCODE" == "true" ]]; then
        DOTNET_SKILLS_TARGET="$TARGET_DIR/.opencode/skills/dotnet-skills"
        if [[ -d "$DOTNET_SKILLS_TARGET" && "$FORCE" != "true" ]]; then
            warn "OpenCode .NET skills already exist (use --force to overwrite)"
        else
            if [[ "$SKIP_DOWNLOAD" == "true" ]]; then
                if [[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR/.opencode/skills/dotnet-skills" ]]; then
                    mkdir -p "$TARGET_DIR/.opencode/skills"
                    cp -r "$SOURCE_DIR/.opencode/skills/dotnet-skills" "$DOTNET_SKILLS_TARGET"
                    count=$(find "$DOTNET_SKILLS_TARGET" -type f | wc -l)
                    success "Copied .NET skills to OpenCode from local source ($count files)"
                fi
            elif [[ -n "$DOTNET_EXTRACTED" ]]; then
                mkdir -p "$DOTNET_SKILLS_TARGET"
                if [[ -d "$DOTNET_EXTRACTED/plugins" ]]; then
                    for category_dir in "$DOTNET_EXTRACTED/plugins/"*/; do
                        [[ ! -d "$category_dir" ]] && continue
                        category=$(basename "$category_dir")
                        [[ "$category" == "dotnet" ]] && category="dotnet-core"
                        skills_dir="$category_dir/skills"
                        [[ ! -d "$skills_dir" ]] && continue
                        for skill_dir in "$skills_dir"/*/; do
                            [[ ! -d "$skill_dir" ]] && continue
                            skill_name=$(basename "$skill_dir")
                            [[ ! -f "$skill_dir/SKILL.md" ]] && continue
                            dest="$DOTNET_SKILLS_TARGET/${category}/${skill_name}"
                            mkdir -p "$dest"
                            cp "$skill_dir/SKILL.md" "$dest/SKILL.md"
                            [[ -d "$skill_dir/references" ]] && cp -r "$skill_dir/references" "$dest/"
                        done
                    done
                fi
                # Create main router SKILL.md
                ROUTER="$DOTNET_SKILLS_TARGET/dotnet-developer/SKILL.md"
                if [[ ! -f "$ROUTER" ]]; then
                    mkdir -p "$DOTNET_SKILLS_TARGET/dotnet-developer"
                    create_dotnet_router "$ROUTER"
                fi
                count=$(find "$DOTNET_SKILLS_TARGET" -name "SKILL.md" 2>/dev/null | wc -l)
                [[ $count -gt 0 ]] && success "Copied .NET skills to OpenCode ($count files)"
            fi
        fi
    fi

    # ── Claude: .claude/skills/dotnet-developer/ (individual skill dirs) ──
    if [[ "$HAS_CLAUDE" == "true" ]]; then
        CLAUDE_DOTNET="$TARGET_DIR/.claude/skills/dotnet-developer"
        if [[ -d "$CLAUDE_DOTNET" && "$FORCE" != "true" ]]; then
            warn "Claude .NET skills already exist (use --force to overwrite)"
        else
            if [[ "$SKIP_DOWNLOAD" == "true" ]]; then
                if [[ -n "$SOURCE_DIR" && -d "$SOURCE_DIR/.claude/skills/dotnet-developer" ]]; then
                    mkdir -p "$CLAUDE_DOTNET"
                    cp -r "$SOURCE_DIR/.claude/skills/dotnet-developer/"* "$CLAUDE_DOTNET/"
                    success "Copied .NET skills to Claude from local source"
                fi
            elif [[ -n "$DOTNET_EXTRACTED" ]]; then
                # Copy .NET skills flattened: each category-skill becomes a Claude skill
                if [[ -d "$DOTNET_EXTRACTED/plugins" ]]; then
                    for category_dir in "$DOTNET_EXTRACTED/plugins/"*/; do
                        [[ ! -d "$category_dir" ]] && continue
                        category=$(basename "$category_dir")
                        [[ "$category" == "dotnet" ]] && category="dotnet-core"
                        skills_dir="$category_dir/skills"
                        [[ ! -d "$skills_dir" ]] && continue
                        for skill_dir in "$skills_dir"/*/; do
                            [[ ! -d "$skill_dir" ]] && continue
                            skill_name=$(basename "$skill_dir")
                            [[ ! -f "$skill_dir/SKILL.md" ]] && continue
                            # Claude skill path: .claude/skills/dotnet-<category>-<skill>/
                            claude_skill_name="dotnet-${category}-${skill_name}"
                            dest="$TARGET_DIR/.claude/skills/$claude_skill_name"
                            mkdir -p "$dest"
                            cp "$skill_dir/SKILL.md" "$dest/SKILL.md"
                            [[ -d "$skill_dir/references" ]] && cp -r "$skill_dir/references" "$dest/"
                        done
                    done
                fi
                # Create router skill
                CLAUDE_ROUTER="$TARGET_DIR/.claude/skills/dotnet-developer/SKILL.md"
                if [[ ! -f "$CLAUDE_ROUTER" ]]; then
                    mkdir -p "$TARGET_DIR/.claude/skills/dotnet-developer"
                    create_dotnet_router "$CLAUDE_ROUTER"
                fi
                count=$(find "$TARGET_DIR/.claude/skills/" -name "SKILL.md" 2>/dev/null | wc -l)
                [[ $count -gt 0 ]] && success "Copied .NET skills to Claude ($count files)"
            fi
        fi
    fi
fi

# =============================================================================
# PHASE 4: Create Integration Files
# =============================================================================
header "Phase 4: Integration Files"

# ── 4a. OpenCode: opencode.json ──────────────────────────────────────────────
if [[ "$HAS_OPENCODE" == "true" ]]; then
    OC_FILE="$TARGET_DIR/opencode.json"
    if [[ -f "$OC_FILE" && "$FORCE" != "true" ]]; then
        warn "opencode.json exists (use --force to overwrite)"
    else
        cat > "$OC_FILE" << 'ENDOFJSON'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["AGENTS.md"],
  "permission": { "skill": { "*": "allow" } },
  "command": {
ENDOFJSON

        CMD_COUNT=0

        if [[ "$HAS_ANGULAR" == "true" ]]; then
            cat >> "$OC_FILE" << 'ENDCMD'
    "angular-developer": {
      "description": "Genera componentes, servicios y Signals bajo el flujo AIDLC.",
      "template": "Execute standard Angular tasks using local workspace definitions. Check rules in ./.opencode/skills/angular-skills/angular-developer/SKILL.md. Argument context: $ARGUMENTS"
    },
    "angular-new-app": {
      "description": "Estructura un nuevo espacio de trabajo Angular bajo el flujo AIDLC.",
      "template": "Scaffold a new framework workspace structure. Check guidelines in ./.opencode/skills/angular-skills/angular-new-app/SKILL.md. Argument context: $ARGUMENTS"
    }
ENDCMD
            CMD_COUNT=$((CMD_COUNT + 2))
        fi

        if [[ "$HAS_DOTNET" == "true" ]]; then
            if [[ $CMD_COUNT -gt 0 ]]; then
                sed -i '$ { /^$/d }' "$OC_FILE"
                echo "," >> "$OC_FILE"
            fi
            cat >> "$OC_FILE" << 'ENDCMD'
    "dotnet-developer": {
      "description": "Desarrollo backend .NET: Web API, EF Core, testing, diagnostics y build bajo el flujo AIDLC.",
      "template": "Execute .NET backend development tasks using local workspace definitions. Check rules in ./.opencode/skills/dotnet-skills/dotnet-developer/SKILL.md. Argument context: $ARGUMENTS"
    }
ENDCMD
        fi

        echo ""  >> "$OC_FILE"
        echo "  }" >> "$OC_FILE"
        echo "}" >> "$OC_FILE"
        success "Created opencode.json"
    fi

    # ── OpenCode: AIDLC Extension Bridges (.aidlc-rule-details/extensions/) ──
    EXT_DIR="$TARGET_DIR/.aidlc-rule-details/extensions"

    if [[ "$HAS_ANGULAR" == "true" ]]; then
        ANG_EXT="$EXT_DIR/angular"
        mkdir -p "$ANG_EXT"
        if [[ ! -f "$ANG_EXT/angular.md" || "$FORCE" == "true" ]]; then
            cat > "$ANG_EXT/angular.md" << 'ENDMD'
# Angular Framework Extension Rules

## Context Enforcement
CRITICAL: This extension is ENABLED. The agent must support both the automated AIDLC workflow phases and the manual OpenCode chat commands.

## Local Skills Routing & Commands
- When the user executes the `/angular-developer` command or when generating Angular components/services/signals, read and apply:
  `./.opencode/skills/angular-skills/angular-developer/SKILL.md`
- When creating a new Angular project, use the `/angular-new-app` command which references:
  `./.opencode/skills/angular-skills/angular-new-app/SKILL.md`

## Integration Constraints
- Any code generated via manual commands (/) MUST still satisfy the active phase constraints defined in `aidlc-docs/aidlc-state.md`.
- Always log command executions inside `audit.md`.
ENDMD
            cat > "$ANG_EXT/angular.opt-in.md" << 'ENDMD'
Would you like to enable Angular development patterns (components, signals, routing, SSR) for this development session?
ENDMD
            success "Created Angular extension bridge (OpenCode)"
        fi
    fi

    if [[ "$HAS_DOTNET" == "true" ]]; then
        DOT_EXT="$EXT_DIR/dotnet"
        mkdir -p "$DOT_EXT"
        if [[ ! -f "$DOT_EXT/dotnet.md" || "$FORCE" == "true" ]]; then
            cat > "$DOT_EXT/dotnet.md" << 'ENDMD'
# .NET Framework Extension Rules

## Context Enforcement
CRITICAL: This extension is ENABLED. The agent must support both the automated AIDLC workflow phases and the manual OpenCode chat commands.

## Local Skills Routing & Commands
- When the user executes the `/dotnet-developer` command or when generating .NET backend logic, load the router skill:
  `./.opencode/skills/dotnet-skills/dotnet-developer/SKILL.md`
- The router lists all available .NET sub-skills organized by domain. Use the `skill` tool to load the specific sub-skill needed:
  - Web API → `dotnet-aspnetcore/dotnet-webapi`
  - EF Core → `dotnet-data/optimizing-ef-core-queries`
  - Testing → `dotnet-test/writing-mstest-tests` or `dotnet-test/run-tests`
  - Build/MSBuild → `dotnet-msbuild/build-perf-diagnostics`
  - Diagnostics → `dotnet-diag/analyzing-dotnet-performance`
  - Upgrades → `dotnet-upgrade/migrate-dotnet9-to-dotnet10`

## Integration Constraints
- Any code generated via manual commands (/) MUST still satisfy the active phase constraints defined in `aidlc-docs/aidlc-state.md`.
- Always log command executions inside `audit.md`.
- Follow the project's established conventions for API style, test framework, and package management.
ENDMD
            cat > "$DOT_EXT/dotnet.opt-in.md" << 'ENDMD'
Would you like to enable .NET backend development patterns (ASP.NET Core, EF Core, MSTest) for this development session?
ENDMD
            success "Created .NET extension bridge (OpenCode)"
        fi
    fi
fi

# ── 4b. Claude: settings.json + extension rules (.claude/) ──────────────────
if [[ "$HAS_CLAUDE" == "true" ]]; then
    CLAUDE_DIR="$TARGET_DIR/.claude"
    mkdir -p "$CLAUDE_DIR"

    # Claude settings.json
    CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
    if [[ ! -f "$CLAUDE_SETTINGS" || "$FORCE" == "true" ]]; then
        cat > "$CLAUDE_SETTINGS" << 'ENDJSON'
{
  "permissions": {
    "allow": [
      "Read",
      "Edit",
      "Write",
      "Bash(git *)",
      "Bash(dotnet *)",
      "Bash(npm *)",
      "Bash(ng *)"
    ]
  }
}
ENDJSON
        success "Created .claude/settings.json"
    fi

    # Claude extension rules for Angular
    if [[ "$HAS_ANGULAR" == "true" ]]; then
        CLAUDE_ANG_RULE="$CLAUDE_DIR/rules/angular-extension.md"
        if [[ ! -f "$CLAUDE_ANG_RULE" || "$FORCE" == "true" ]]; then
            cat > "$CLAUDE_ANG_RULE" << 'ENDMD'
---
paths:
  - "**/*.ts"
  - "**/*.html"
  - "**/*.scss"
  - "**/*.css"
---
# Angular Framework Extension

## Context Enforcement
CRITICAL: This extension is ENABLED. The agent must support both the automated AIDLC workflow phases and the manual Claude commands.

## Local Skills Routing
- When generating Angular components, services, or signals, read and apply:
  `@.claude/skills/angular-developer/SKILL.md`
- When creating a new Angular project:
  `@.claude/skills/angular-new-app/SKILL.md`

## Integration Constraints
- Any code generated MUST satisfy the active phase constraints defined in `aidlc-docs/aidlc-state.md`.
- Always log command executions inside `audit.md`.
ENDMD
            success "Created Angular extension rule (Claude)"
        fi
    fi

    # Claude extension rules for .NET
    if [[ "$HAS_DOTNET" == "true" ]]; then
        CLAUDE_DOT_RULE="$CLAUDE_DIR/rules/dotnet-extension.md"
        if [[ ! -f "$CLAUDE_DOT_RULE" || "$FORCE" == "true" ]]; then
            cat > "$CLAUDE_DOT_RULE" << 'ENDMD'
---
paths:
  - "**/*.cs"
  - "**/*.csproj"
  - "**/*.sln"
  - "**/*.json"
---
# .NET Framework Extension

## Context Enforcement
CRITICAL: This extension is ENABLED. The agent must support both the automated AIDLC workflow phases and the manual Claude commands.

## Local Skills Routing
- When generating .NET backend logic, load the router skill:
  `@.claude/skills/dotnet-developer/SKILL.md`
- The router lists all available .NET sub-skills organized by domain.

## Integration Constraints
- Any code generated MUST satisfy the active phase constraints defined in `aidlc-docs/aidlc-state.md`.
- Always log command executions inside `audit.md`.
- Follow the project's established conventions for API style, test framework, and package management.
ENDMD
            success "Created .NET extension rule (Claude)"
        fi
    fi
fi

# ── 4c. .gitignore ──────────────────────────────────────────────────────────
GI_FILE="$TARGET_DIR/.gitignore"
if [[ -f "$GI_FILE" ]]; then
    added=0
    for entry in ".aidlc-rule-details" "aidlc-docs/"; do
        if ! grep -qF "$entry" "$GI_FILE" 2>/dev/null; then
            echo "$entry" >> "$GI_FILE"
            added=$((added + 1))
        fi
    done
    if [[ "$HAS_CLAUDE" == "true" ]]; then
        for entry in ".claude/settings.local.json" ".claude/CLAUDE.local.md"; do
            if ! grep -qF "$entry" "$GI_FILE" 2>/dev/null; then
                echo "$entry" >> "$GI_FILE"
                added=$((added + 1))
            fi
        done
    fi
    [[ $added -gt 0 ]] && success "Updated .gitignore (+$added entries)"
else
    {
        echo "# AIDLC Environment"
        echo ".aidlc-rule-details"
        echo "aidlc-docs/"
        if [[ "$HAS_CLAUDE" == "true" ]]; then
            echo ".claude/settings.local.json"
            echo ".claude/CLAUDE.local.md"
        fi
    } > "$GI_FILE"
    success "Created .gitignore"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "  Project: $TARGET_DIR"
echo "  Agent:   $AGENT"
echo ""

echo "  Installed components:"

# OpenCode components
if [[ "$HAS_OPENCODE" == "true" ]]; then
    [[ -d "$AIDLC_TARGET" ]] && echo "    ✓ AIDLC rules       (.aidlc-rule-details/)"
    [[ -f "$AGENTS_FILE" ]]  && echo "    ✓ AGENTS.md          (core workflow - OpenCode)"
    [[ "$HAS_ANGULAR" == "true" && -d "$TARGET_DIR/.opencode/skills/angular-skills" ]] && \
        echo "    ✓ Angular skills     (.opencode/skills/angular-skills/)"
    [[ "$HAS_DOTNET" == "true" && -d "$TARGET_DIR/.opencode/skills/dotnet-skills" ]] && \
        echo "    ✓ .NET skills        (.opencode/skills/dotnet-skills/)"
    echo "    ✓ opencode.json      (commands registered)"
    echo "    ✓ AIDLC extensions   (.aidlc-rule-details/extensions/)"
fi

# Claude components
if [[ "$HAS_CLAUDE" == "true" ]]; then
    [[ -f "$CLAUDE_FILE" ]] && echo "    ✓ CLAUDE.md           (core workflow - Claude)"
    [[ -d "$TARGET_DIR/.claude/rules" ]] && echo "    ✓ .claude/rules/      (AIDLC rules for Claude)"
    [[ "$HAS_ANGULAR" == "true" && -d "$TARGET_DIR/.claude/skills/angular-developer" ]] && \
        echo "    ✓ Angular skills     (.claude/skills/angular-developer/)"
    [[ "$HAS_DOTNET" == "true" && -d "$TARGET_DIR/.claude/skills/dotnet-developer" ]] && \
        echo "    ✓ .NET skills        (.claude/skills/dotnet-developer/)"
    [[ -f "$TARGET_DIR/.claude/settings.json" ]] && echo "    ✓ .claude/settings.json"
    echo "    ✓ Claude extensions  (.claude/rules/*-extension.md)"
fi

echo "    ✓ .gitignore         (updated)"
echo ""
info "Note: aidlc-docs/ is created automatically by the AIDLC workflow on first run"
echo ""
info "Sources:"
echo "    AIDLC:   https://github.com/awslabs/aidlc-workflows"
echo "    Angular: https://github.com/angular/skills"
echo "    .NET:    https://github.com/dotnet/skills"
echo ""
if [[ "$HAS_OPENCODE" == "true" ]]; then
    info "OpenCode: Start a new session and use /angular-developer or /dotnet-developer"
fi
if [[ "$HAS_CLAUDE" == "true" ]]; then
    info "Claude:   Start a new session — skills load automatically from .claude/skills/"
fi
