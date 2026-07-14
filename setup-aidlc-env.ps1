# =============================================================================
# AIDLC Environment Setup Script (PowerShell - Windows)
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
#   .\setup-aidlc-env.ps1 -TargetDir C:\path\to\project [OPTIONS]
#
# Options:
#   -TargetDir DIR      Target project directory (required)
#   -Agent AGENT        Target agent: opencode, claude, or both (default: opencode)
#   -Frameworks LIST    Comma-separated: angular,dotnet,both (default: both)
#   -Force              Overwrite existing files
#   -SkipDownload       Use local source dir instead of downloading
#   -SourceDir DIR      Local source for -SkipDownload mode
#   -AidlcRef REF       Git ref for AIDLC (default: main)
#   -AngularRef REF     Git ref for Angular skills (default: main)
#   -DotnetRef REF      Git ref for .NET skills (default: main)
#   -Help               Show this help
# =============================================================================

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TargetDir = "",

    [ValidateSet("opencode", "claude", "both")]
    [string]$Agent = "opencode",

    [ValidateSet("angular", "dotnet", "both")]
    [string]$Frameworks = "both",

    [switch]$Force,

    [switch]$SkipDownload,

    [string]$SourceDir = "",

    [string]$AidlcRef = "main",

    [string]$AngularRef = "main",

    [string]$DotnetRef = "main",

    [switch]$Help
)

$ErrorActionPreference = "Stop"

# ── Colors ────────────────────────────────────────────────────────────────────
function Write-Info    { param([string]$Msg) Write-Host "[INFO] $Msg" -ForegroundColor Blue }
function Write-Success { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "[WARN] $Msg" -ForegroundColor Yellow }
function Write-Error2  { param([string]$Msg) Write-Host "[ERROR] $Msg" -ForegroundColor Red }
function Write-Header  { param([string]$Msg) Write-Host "`n=== $Msg ===" -ForegroundColor Cyan }

# ── Help ──────────────────────────────────────────────────────────────────────
if ($Help) {
    Get-Content -Path $PSCommandPath | Select-Object -First 35 | ForEach-Object {
        if ($_ -match '^#\s*(.*)') { $matches[1] }
    }
    exit 0
}

# ── Parse Args ────────────────────────────────────────────────────────────────
if (-not $TargetDir) {
    Write-Error2 "Usage: $($MyInvocation.MyCommand.Name) -TargetDir <path> [-Agent opencode|claude|both] [-Frameworks angular|dotnet|both]"
    exit 1
}

$HasOpenCode = $false
$HasClaude = $false
if ($Agent -eq "opencode" -or $Agent -eq "both") { $HasOpenCode = $true }
if ($Agent -eq "claude" -or $Agent -eq "both") { $HasClaude = $true }

# ── Validate Dependencies ─────────────────────────────────────────────────────
foreach ($cmd in @("curl", "tar")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error2 "Required command not found: $cmd"
        exit 1
    }
}

# ── Prepare ───────────────────────────────────────────────────────────────────
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}
$TargetDir = (Resolve-Path $TargetDir).Path

$CacheDir = Join-Path ([System.IO.Path]::GetTempPath()) "aidlc-setup-$(Get-Random)"
New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null

# Cleanup on exit
try {
    $script:HasAngular = $false
    $script:HasDotnet = $false
    if ($Frameworks -eq "angular" -or $Frameworks -eq "both") { $script:HasAngular = $true }
    if ($Frameworks -eq "dotnet" -or $Frameworks -eq "both") { $script:HasDotnet = $true }

    Write-Host ""
    Write-Host "============================================"
    Write-Host "  AIDLC Environment Setup (PowerShell)"
    Write-Host "============================================"
    Write-Info "Target:      $TargetDir"
    Write-Info "Agent:       $Agent"
    Write-Info "Frameworks:  $Frameworks"
    Write-Info "Download:    $(if ($SkipDownload) { 'no (local)' } else { 'yes (official repos)' })"
    Write-Host ""

    # Helper: Download and extract a tar.gz from GitHub
    function Get-GitHubTarball {
        param(
            [string]$Url,
            [string]$ExtractDir,
            [string]$FilterPattern
        )
        $tarFile = Join-Path $CacheDir ([System.IO.Path]::GetFileName($Url))
        try {
            Invoke-WebRequest -Uri $Url -OutFile $tarFile -UseBasicParsing -ErrorAction Stop
        } catch {
            return $null
        }
        if (-not (Test-Path $tarFile)) { return $null }

        New-Item -ItemType Directory -Path $ExtractDir -Force | Out-Null
        tar -xzf $tarFile -C $ExtractDir 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }

        $found = Get-ChildItem -Path $ExtractDir -Directory | Where-Object { $_.Name -like $FilterPattern } | Select-Object -First 1
        return $found?.FullName
    }

    # Helper: Count files recursively
    function Get-FileCount {
        param([string]$Path, [string]$Pattern = "*")
        if (-not (Test-Path $Path)) { return 0 }
        return @(Get-ChildItem -Path $Path -Recurse -Filter $Pattern -File).Count
    }

    # Helper: Copy directory recursively
    function Copy-DirRecursive {
        param([string]$Source, [string]$Destination)
        if (-not (Test-Path $Source)) { return }
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        Copy-Item -Path (Join-Path $Source "*") -Destination $Destination -Recurse -Force
    }

    # =============================================================================
    # PHASE 1: Download AIDLC Rules from Official Repo
    # =============================================================================
    Write-Header "Phase 1: AIDLC Rules (awslabs/aidlc-workflows)"

    $AidlcTarget = Join-Path $TargetDir ".aidlc-rule-details"
    if ((Test-Path $AidlcTarget) -and -not $Force) {
        Write-Warn ".aidlc-rule-details/ already exists (use -Force to overwrite)"
    } else {
        if ($SkipDownload) {
            if ($SourceDir -and (Test-Path (Join-Path $SourceDir ".aidlc-rule-details"))) {
                Copy-DirRecursive (Join-Path $SourceDir ".aidlc-rule-details") $AidlcTarget
                $count = Get-FileCount $AidlcTarget "*.md"
                Write-Success "Copied $count AIDLC rule files from local source"
            } else {
                Write-Warn "No local .aidlc-rule-details found, skipping"
            }
        } else {
            Write-Info "Downloading AIDLC rules (ref: $AidlcRef)..."
            $aidlcUrl = "https://github.com/awslabs/aidlc-workflows/archive/refs/heads/${AidlcRef}.tar.gz"
            $aidlcExtractDir = Join-Path $CacheDir "aidlc-extract"

            $aidlcExtracted = Get-GitHubTarball -Url $aidlcUrl -ExtractDir $aidlcExtractDir -FilterPattern "aidlc-workflows-*"

            if ($aidlcExtracted) {
                $found = $false
                # Try official structure
                $checkPath = Join-Path $aidlcExtracted "aidlc-rules\aws-aidlc-rule-details"
                if (Test-Path $checkPath) {
                    Copy-DirRecursive $checkPath $AidlcTarget
                    $found = $true
                } else {
                    $checkPath2 = Join-Path $aidlcExtracted ".aidlc-rule-details"
                    if (Test-Path $checkPath2) {
                        Copy-DirRecursive $checkPath2 $AidlcTarget
                        $found = $true
                    } else {
                        # Fallback: search for any aidlc-rule-details directory
                        $dirs = Get-ChildItem -Path $aidlcExtracted -Directory -Recurse | Where-Object { $_.Name -like "*aidlc-rule-details" } | Select-Object -First 1
                        if ($dirs) {
                            Copy-DirRecursive $dirs.FullName $AidlcTarget
                            $found = $true
                        }
                    }
                }
                if ($found) {
                    $count = Get-FileCount $AidlcTarget "*.md"
                    Write-Success "Downloaded and extracted $count AIDLC rule files"
                } else {
                    Write-Error2 "Could not find aidlc-rule-details in downloaded repo"
                    exit 1
                }
            } else {
                Write-Error2 "Failed to download AIDLC rules from $aidlcUrl"
                exit 1
            }
        }
    }

    # Also set up AGENTS.md / CLAUDE.md from AIDLC core workflow
    $AgentsFile = Join-Path $TargetDir "AGENTS.md"
    $ClaudeFile = Join-Path $TargetDir "CLAUDE.md"

    $CoreWorkflow = $null
    if ($SkipDownload) {
        if ($SourceDir -and (Test-Path (Join-Path $SourceDir "AGENTS.md"))) {
            $CoreWorkflow = Join-Path $SourceDir "AGENTS.md"
        }
    } else {
        $aidlcExtracted = Get-ChildItem -Path $CacheDir -Directory | Where-Object { $_.Name -like "aidlc-workflows-*" } | Select-Object -First 1
        if ($aidlcExtracted) {
            $checkFile = Join-Path $aidlcExtracted.FullName "aidlc-rules\aws-aidlc-rules\core-workflow.md"
            if (Test-Path $checkFile) {
                $CoreWorkflow = $checkFile
            } else {
                $checkFile2 = Join-Path $aidlcExtracted.FullName "AGENTS.md"
                if (Test-Path $checkFile2) { $CoreWorkflow = $checkFile2 }
            }
        }
    }

    # Create AGENTS.md for OpenCode
    if ($HasOpenCode -and $CoreWorkflow) {
        if (-not (Test-Path $AgentsFile) -or $Force) {
            Copy-Item $CoreWorkflow $AgentsFile -Force
            Write-Success "Copied AGENTS.md from AIDLC core workflow"
        }
    }

    # Create CLAUDE.md for Claude Code
    if ($HasClaude -and $CoreWorkflow) {
        if (-not (Test-Path $ClaudeFile) -or $Force) {
            Copy-Item $CoreWorkflow $ClaudeFile -Force
            Write-Success "Copied CLAUDE.md from AIDLC core workflow"
        }
        $ClaudeRulesDir = Join-Path $TargetDir ".claude\rules\aidlc"
        if (-not (Test-Path $ClaudeRulesDir) -or $Force) {
            if (Test-Path $AidlcTarget) {
                New-Item -ItemType Directory -Path $ClaudeRulesDir -Force | Out-Null
                Copy-Item -Path (Join-Path $AidlcTarget "*") -Destination $ClaudeRulesDir -Recurse -Force
                $count = Get-FileCount $ClaudeRulesDir "*.md"
                Write-Success "Copied $count AIDLC rules to .claude/rules/aidlc/"
            }
        }
    }

    # ── Helper: Create .NET router SKILL.md ──────────────────────────────────────
    function New-DotnetRouter {
        param([string]$Dest)
        $routerContent = @'
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
- `dotnet-test-migration/migrate-mstest-v1v2-to-v3` — MSTest v1/v2 -> v3
- `dotnet-test-migration/migrate-mstest-v3-to-v4` — MSTest v3 -> v4
- `dotnet-test-migration/migrate-xunit-to-mstest` — xUnit -> MSTest
- `dotnet-test-migration/migrate-xunit-to-xunit-v3` — xUnit v2 -> v3
- `dotnet-test-migration/migrate-vstest-to-mtp` — VSTest -> Microsoft.Testing.Platform

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
- `dotnet-upgrade/migrate-dotnet8-to-dotnet9` — .NET 8 -> 9
- `dotnet-upgrade/migrate-dotnet9-to-dotnet10` — .NET 9 -> 10
- `dotnet-upgrade/migrate-dotnet10-to-dotnet11` — .NET 10 -> 11
- `dotnet-upgrade/dotnet-aot-compat` — AOT/trimming compatibility
- `dotnet-upgrade/migrate-nullable-references` — Enable nullable references
- `dotnet-upgrade/thread-abort-migration` — Thread.Abort -> cancellation

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
'@
        Set-Content -Path $Dest -Value $routerContent -Encoding UTF8
    }

    # =============================================================================
    # PHASE 2: Download Angular Skills from Official Repo
    # =============================================================================
    if ($script:HasAngular) {
        Write-Header "Phase 2: Angular Skills (angular/skills)"

        $AngularExtracted = $null
        if (-not $SkipDownload) {
            Write-Info "Downloading Angular skills (ref: $AngularRef)..."
            $angularUrl = "https://github.com/angular/skills/archive/refs/heads/${AngularRef}.tar.gz"
            $angularExtractDir = Join-Path $CacheDir "angular-extract"
            $AngularExtracted = Get-GitHubTarball -Url $angularUrl -ExtractDir $angularExtractDir -FilterPattern "skills-*"
            if (-not $AngularExtracted) {
                Write-Error2 "Failed to extract Angular skills"
            }
        }

        # OpenCode: .opencode/skills/angular-skills/
        if ($HasOpenCode) {
            $AngularSkillsTarget = Join-Path $TargetDir ".opencode\skills\angular-skills"
            if ((Test-Path $AngularSkillsTarget) -and -not $Force) {
                Write-Warn "OpenCode Angular skills already exist (use -Force to overwrite)"
            } else {
                if ($SkipDownload) {
                    $srcPath = Join-Path $SourceDir ".opencode\skills\angular-skills"
                    if ($SourceDir -and (Test-Path $srcPath)) {
                        New-Item -ItemType Directory -Path (Split-Path $AngularSkillsTarget) -Force | Out-Null
                        Copy-DirRecursive $srcPath $AngularSkillsTarget
                        $count = Get-FileCount $AngularSkillsTarget
                        Write-Success "Copied Angular skills to OpenCode ($count files)"
                    }
                } elseif ($AngularExtracted) {
                    New-Item -ItemType Directory -Path $AngularSkillsTarget -Force | Out-Null
                    $devPath = Join-Path $AngularExtracted "angular-developer"
                    $newPath = Join-Path $AngularExtracted "angular-new-app"
                    if (Test-Path $devPath) { Copy-DirRecursive $devPath (Join-Path $AngularSkillsTarget "angular-developer") }
                    if (Test-Path $newPath) { Copy-DirRecursive $newPath (Join-Path $AngularSkillsTarget "angular-new-app") }
                    $count = Get-FileCount $AngularSkillsTarget
                    if ($count -gt 0) { Write-Success "Copied Angular skills to OpenCode ($count files)" }
                }
            }
        }

        # Claude: .claude/skills/angular-developer/ + angular-new-app/
        if ($HasClaude) {
            $ClaudeAngDev = Join-Path $TargetDir ".claude\skills\angular-developer"
            $ClaudeAngNew = Join-Path $TargetDir ".claude\skills\angular-new-app"
            if ((Test-Path $ClaudeAngDev) -and (Test-Path $ClaudeAngNew) -and -not $Force) {
                Write-Warn "Claude Angular skills already exist (use -Force to overwrite)"
            } else {
                if ($SkipDownload) {
                    if ($SourceDir) {
                        $srcDev = Join-Path $SourceDir ".claude\skills\angular-developer"
                        $srcNew = Join-Path $SourceDir ".claude\skills\angular-new-app"
                        if (Test-Path $srcDev) { Copy-DirRecursive $srcDev $ClaudeAngDev }
                        if (Test-Path $srcNew) { Copy-DirRecursive $srcNew $ClaudeAngNew }
                        Write-Success "Copied Angular skills to Claude from local source"
                    }
                } elseif ($AngularExtracted) {
                    $devPath = Join-Path $AngularExtracted "angular-developer"
                    $newPath = Join-Path $AngularExtracted "angular-new-app"
                    if (Test-Path $devPath) {
                        New-Item -ItemType Directory -Path $ClaudeAngDev -Force | Out-Null
                        Copy-Item -Path (Join-Path $devPath "*") -Destination $ClaudeAngDev -Recurse -Force
                    }
                    if (Test-Path $newPath) {
                        New-Item -ItemType Directory -Path $ClaudeAngNew -Force | Out-Null
                        Copy-Item -Path (Join-Path $newPath "*") -Destination $ClaudeAngNew -Recurse -Force
                    }
                    $count = Get-FileCount (Join-Path $TargetDir ".claude\skills")
                    if ($count -gt 0) { Write-Success "Copied Angular skills to Claude ($count files)" }
                }
            }
        }
    }

    # =============================================================================
    # PHASE 3: Download .NET Skills from Official Repo
    # =============================================================================
    if ($script:HasDotnet) {
        Write-Header "Phase 3: .NET Skills (dotnet/skills)"

        $DotnetExtracted = $null
        if (-not $SkipDownload) {
            Write-Info "Downloading .NET skills (ref: $DotnetRef)..."
            $dotnetUrl = "https://github.com/dotnet/skills/archive/refs/heads/${DotnetRef}.tar.gz"
            $dotnetExtractDir = Join-Path $CacheDir "dotnet-extract"
            $DotnetExtracted = Get-GitHubTarball -Url $dotnetUrl -ExtractDir $dotnetExtractDir -FilterPattern "skills-*"
            if (-not $DotnetExtracted) {
                Write-Error2 "Failed to extract .NET skills"
            }
        }

        # OpenCode: .opencode/skills/dotnet-skills/
        if ($HasOpenCode) {
            $DotnetSkillsTarget = Join-Path $TargetDir ".opencode\skills\dotnet-skills"
            if ((Test-Path $DotnetSkillsTarget) -and -not $Force) {
                Write-Warn "OpenCode .NET skills already exist (use -Force to overwrite)"
            } else {
                if ($SkipDownload) {
                    $srcPath = Join-Path $SourceDir ".opencode\skills\dotnet-skills"
                    if ($SourceDir -and (Test-Path $srcPath)) {
                        New-Item -ItemType Directory -Path (Split-Path $DotnetSkillsTarget) -Force | Out-Null
                        Copy-DirRecursive $srcPath $DotnetSkillsTarget
                        $count = Get-FileCount $DotnetSkillsTarget "SKILL.md"
                        Write-Success "Copied .NET skills to OpenCode from local source ($count files)"
                    }
                } elseif ($DotnetExtracted) {
                    New-Item -ItemType Directory -Path $DotnetSkillsTarget -Force | Out-Null
                    $pluginsPath = Join-Path $DotnetExtracted "plugins"
                    if (Test-Path $pluginsPath) {
                        Get-ChildItem -Path $pluginsPath -Directory | ForEach-Object {
                            $category = $_.Name
                            if ($category -eq "dotnet") { $category = "dotnet-core" }
                            $skillsDir = Join-Path $_.FullName "skills"
                            if (-not (Test-Path $skillsDir)) { return }
                            Get-ChildItem -Path $skillsDir -Directory | ForEach-Object {
                                $skillName = $_.Name
                                if (-not (Test-Path (Join-Path $_.FullName "SKILL.md"))) { return }
                                $dest = Join-Path $DotnetSkillsTarget "$category\$skillName"
                                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                                Copy-Item (Join-Path $_.FullName "SKILL.md") (Join-Path $dest "SKILL.md") -Force
                                $refsDir = Join-Path $_.FullName "references"
                                if (Test-Path $refsDir) {
                                    Copy-DirRecursive $refsDir (Join-Path $dest "references")
                                }
                            }
                        }
                    }
                    # Create main router SKILL.md
                    $router = Join-Path $DotnetSkillsTarget "dotnet-developer\SKILL.md"
                    if (-not (Test-Path $router)) {
                        New-Item -ItemType Directory -Path (Split-Path $router) -Force | Out-Null
                        New-DotnetRouter $router
                    }
                    $count = Get-FileCount $DotnetSkillsTarget "SKILL.md"
                    if ($count -gt 0) { Write-Success "Copied .NET skills to OpenCode ($count files)" }
                }
            }
        }

        # Claude: .claude/skills/dotnet-developer/ (individual skill dirs)
        if ($HasClaude) {
            $ClaudeDotnet = Join-Path $TargetDir ".claude\skills\dotnet-developer"
            if ((Test-Path $ClaudeDotnet) -and -not $Force) {
                Write-Warn "Claude .NET skills already exist (use -Force to overwrite)"
            } else {
                if ($SkipDownload) {
                    $srcPath = Join-Path $SourceDir ".claude\skills\dotnet-developer"
                    if ($SourceDir -and (Test-Path $srcPath)) {
                        New-Item -ItemType Directory -Path $ClaudeDotnet -Force | Out-Null
                        Copy-Item -Path (Join-Path $srcPath "*") -Destination $ClaudeDotnet -Recurse -Force
                        Write-Success "Copied .NET skills to Claude from local source"
                    }
                } elseif ($DotnetExtracted) {
                    $pluginsPath = Join-Path $DotnetExtracted "plugins"
                    if (Test-Path $pluginsPath) {
                        Get-ChildItem -Path $pluginsPath -Directory | ForEach-Object {
                            $category = $_.Name
                            if ($category -eq "dotnet") { $category = "dotnet-core" }
                            $skillsDir = Join-Path $_.FullName "skills"
                            if (-not (Test-Path $skillsDir)) { return }
                            Get-ChildItem -Path $skillsDir -Directory | ForEach-Object {
                                $skillName = $_.Name
                                if (-not (Test-Path (Join-Path $_.FullName "SKILL.md"))) { return }
                                $claudeSkillName = "dotnet-$category-$skillName"
                                $dest = Join-Path $TargetDir ".claude\skills\$claudeSkillName"
                                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                                Copy-Item (Join-Path $_.FullName "SKILL.md") (Join-Path $dest "SKILL.md") -Force
                                $refsDir = Join-Path $_.FullName "references"
                                if (Test-Path $refsDir) {
                                    Copy-DirRecursive $refsDir (Join-Path $dest "references")
                                }
                            }
                        }
                    }
                    # Create router skill
                    $claudeRouter = Join-Path $TargetDir ".claude\skills\dotnet-developer\SKILL.md"
                    if (-not (Test-Path $claudeRouter)) {
                        New-Item -ItemType Directory -Path (Split-Path $claudeRouter) -Force | Out-Null
                        New-DotnetRouter $claudeRouter
                    }
                    $count = Get-FileCount (Join-Path $TargetDir ".claude\skills") "SKILL.md"
                    if ($count -gt 0) { Write-Success "Copied .NET skills to Claude ($count files)" }
                }
            }
        }
    }

    # =============================================================================
    # PHASE 4: Create Integration Files
    # =============================================================================
    Write-Header "Phase 4: Integration Files"

    # ── 4a. OpenCode: opencode.json ──────────────────────────────────────────────
    if ($HasOpenCode) {
        $ocFile = Join-Path $TargetDir "opencode.json"
        if ((Test-Path $ocFile) -and -not $Force) {
            Write-Warn "opencode.json exists (use -Force to overwrite)"
        } else {
            $jsonObj = [ordered]@{
                '$schema' = "https://opencode.ai/config.json"
                instructions = @("AGENTS.md")
                permission = @{ skill = @{ '*' = "allow" } }
                command = [ordered]@{}
            }

            if ($script:HasAngular) {
                $jsonObj.command['angular-developer'] = @{
                    description = "Genera componentes, servicios y Signals bajo el flujo AIDLC."
                    template = "Execute standard Angular tasks using local workspace definitions. Check rules in ./.opencode/skills/angular-skills/angular-developer/SKILL.md. Argument context: `$ARGUMENTS"
                }
                $jsonObj.command['angular-new-app'] = @{
                    description = "Estructura un nuevo espacio de trabajo Angular bajo el flujo AIDLC."
                    template = "Scaffold a new framework workspace structure. Check guidelines in ./.opencode/skills/angular-skills/angular-new-app/SKILL.md. Argument context: `$ARGUMENTS"
                }
            }

            if ($script:HasDotnet) {
                $jsonObj.command['dotnet-developer'] = @{
                    description = "Desarrollo backend .NET: Web API, EF Core, testing, diagnostics y build bajo el flujo AIDLC."
                    template = "Execute .NET backend development tasks using local workspace definitions. Check rules in ./.opencode/skills/dotnet-skills/dotnet-developer/SKILL.md. Argument context: `$ARGUMENTS"
                }
            }

            $jsonObj | ConvertTo-Json -Depth 10 | Set-Content -Path $ocFile -Encoding UTF8
            Write-Success "Created opencode.json"
        }

        # OpenCode: AIDLC Extension Bridges
        $extDir = Join-Path $TargetDir ".aidlc-rule-details\extensions"

        if ($script:HasAngular) {
            $angExt = Join-Path $extDir "angular"
            if (-not (Test-Path (Join-Path $angExt "angular.md")) -or $Force) {
                New-Item -ItemType Directory -Path $angExt -Force | Out-Null
                Set-Content -Path (Join-Path $angExt "angular.md") -Value @'
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
'@ -Encoding UTF8
                Set-Content -Path (Join-Path $angExt "angular.opt-in.md") -Value @'
Would you like to enable Angular development patterns (components, signals, routing, SSR) for this development session?
'@ -Encoding UTF8
                Write-Success "Created Angular extension bridge (OpenCode)"
            }
        }

        if ($script:HasDotnet) {
            $dotExt = Join-Path $extDir "dotnet"
            if (-not (Test-Path (Join-Path $dotExt "dotnet.md")) -or $Force) {
                New-Item -ItemType Directory -Path $dotExt -Force | Out-Null
                Set-Content -Path (Join-Path $dotExt "dotnet.md") -Value @'
# .NET Framework Extension Rules

## Context Enforcement
CRITICAL: This extension is ENABLED. The agent must support both the automated AIDLC workflow phases and the manual OpenCode chat commands.

## Local Skills Routing & Commands
- When the user executes the `/dotnet-developer` command or when generating .NET backend logic, load the router skill:
  `./.opencode/skills/dotnet-skills/dotnet-developer/SKILL.md`
- The router lists all available .NET sub-skills organized by domain. Use the `skill` tool to load the specific sub-skill needed:
  - Web API -> `dotnet-aspnetcore/dotnet-webapi`
  - EF Core -> `dotnet-data/optimizing-ef-core-queries`
  - Testing -> `dotnet-test/writing-mstest-tests` or `dotnet-test/run-tests`
  - Build/MSBuild -> `dotnet-msbuild/build-perf-diagnostics`
  - Diagnostics -> `dotnet-diag/analyzing-dotnet-performance`
  - Upgrades -> `dotnet-upgrade/migrate-dotnet9-to-dotnet10`

## Integration Constraints
- Any code generated via manual commands (/) MUST still satisfy the active phase constraints defined in `aidlc-docs/aidlc-state.md`.
- Always log command executions inside `audit.md`.
- Follow the project's established conventions for API style, test framework, and package management.
'@ -Encoding UTF8
                Set-Content -Path (Join-Path $dotExt "dotnet.opt-in.md") -Value @'
Would you like to enable .NET backend development patterns (ASP.NET Core, EF Core, MSTest) for this development session?
'@ -Encoding UTF8
                Write-Success "Created .NET extension bridge (OpenCode)"
            }
        }
    }

    # ── 4b. Claude: settings.json + extension rules ────────────────────────────
    if ($HasClaude) {
        $claudeDir = Join-Path $TargetDir ".claude"
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null

        $claudeSettings = Join-Path $claudeDir "settings.json"
        if (-not (Test-Path $claudeSettings) -or $Force) {
            @{
                permissions = @{
                    allow = @(
                        "Read",
                        "Edit",
                        "Write",
                        "Bash(git *)",
                        "Bash(dotnet *)",
                        "Bash(npm *)",
                        "Bash(ng *)"
                    )
                }
            } | ConvertTo-Json -Depth 5 | Set-Content -Path $claudeSettings -Encoding UTF8
            Write-Success "Created .claude/settings.json"
        }

        # Claude extension rules for Angular
        if ($script:HasAngular) {
            $claudeAngRule = Join-Path $claudeDir "rules\angular-extension.md"
            if (-not (Test-Path $claudeAngRule) -or $Force) {
                $rulesDir = Join-Path $claudeDir "rules"
                New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
                Set-Content -Path $claudeAngRule -Value @'
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
'@ -Encoding UTF8
                Write-Success "Created Angular extension rule (Claude)"
            }
        }

        # Claude extension rules for .NET
        if ($script:HasDotnet) {
            $claudeDotRule = Join-Path $claudeDir "rules\dotnet-extension.md"
            if (-not (Test-Path $claudeDotRule) -or $Force) {
                $rulesDir = Join-Path $claudeDir "rules"
                New-Item -ItemType Directory -Path $rulesDir -Force | Out-Null
                Set-Content -Path $claudeDotRule -Value @'
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
'@ -Encoding UTF8
                Write-Success "Created .NET extension rule (Claude)"
            }
        }
    }

    # ── 4c. .gitignore ──────────────────────────────────────────────────────────
    $giFile = Join-Path $TargetDir ".gitignore"
    if (Test-Path $giFile) {
        $giContent = Get-Content $giFile -Raw
        $added = 0
        $entries = @(".aidlc-rule-details", "aidlc-docs/")
        if ($HasClaude) { $entries += @(".claude/settings.local.json", ".claude/CLAUDE.local.md") }
        foreach ($entry in $entries) {
            if ($giContent -notnot [regex]::Escape($entry)) {
                # check if already present
            }
            if (-not ($giContent -match [regex]::Escape($entry))) {
                Add-Content -Path $giFile -Value $entry
                $added++
            }
        }
        if ($added -gt 0) { Write-Success "Updated .gitignore (+$added entries)" }
    } else {
        $lines = @("# AIDLC Environment", ".aidlc-rule-details", "aidlc-docs/")
        if ($HasClaude) { $lines += @(".claude/settings.local.json", ".claude/CLAUDE.local.md") }
        $lines | Set-Content -Path $giFile -Encoding UTF8
        Write-Success "Created .gitignore"
    }

    # =============================================================================
    # Summary
    # =============================================================================
    Write-Host ""
    Write-Host "============================================"
    Write-Host "  Setup Complete!"
    Write-Host "============================================"
    Write-Host ""
    Write-Host "  Project: $TargetDir"
    Write-Host "  Agent:   $Agent"
    Write-Host ""
    Write-Host "  Installed components:"

    # OpenCode components
    if ($HasOpenCode) {
        if (Test-Path $AidlcTarget) { Write-Host "    [x] AIDLC rules       (.aidlc-rule-details/)" }
        if (Test-Path $AgentsFile) { Write-Host "    [x] AGENTS.md          (core workflow - OpenCode)" }
        if ($script:HasAngular -and (Test-Path (Join-Path $TargetDir ".opencode\skills\angular-skills"))) {
            Write-Host "    [x] Angular skills     (.opencode/skills/angular-skills/)"
        }
        if ($script:HasDotnet -and (Test-Path (Join-Path $TargetDir ".opencode\skills\dotnet-skills"))) {
            Write-Host "    [x] .NET skills        (.opencode/skills/dotnet-skills/)"
        }
        Write-Host "    [x] opencode.json      (commands registered)"
        Write-Host "    [x] AIDLC extensions   (.aidlc-rule-details/extensions/)"
    }

    # Claude components
    if ($HasClaude) {
        if (Test-Path $ClaudeFile) { Write-Host "    [x] CLAUDE.md           (core workflow - Claude)" }
        if (Test-Path (Join-Path $TargetDir ".claude\rules")) { Write-Host "    [x] .claude/rules/      (AIDLC rules for Claude)" }
        if ($script:HasAngular -and (Test-Path (Join-Path $TargetDir ".claude\skills\angular-developer"))) {
            Write-Host "    [x] Angular skills     (.claude/skills/angular-developer/)"
        }
        if ($script:HasDotnet -and (Test-Path (Join-Path $TargetDir ".claude\skills\dotnet-developer"))) {
            Write-Host "    [x] .NET skills        (.claude/skills/dotnet-developer/)"
        }
        if (Test-Path (Join-Path $TargetDir ".claude\settings.json")) { Write-Host "    [x] .claude/settings.json" }
        Write-Host "    [x] Claude extensions  (.claude/rules/*-extension.md)"
    }

    Write-Host "    [x] .gitignore         (updated)"
    Write-Host ""
    Write-Info "Note: aidlc-docs/ is created automatically by the AIDLC workflow on first run"
    Write-Host ""
    Write-Info "Sources:"
    Write-Host "    AIDLC:   https://github.com/awslabs/aidlc-workflows"
    Write-Host "    Angular: https://github.com/angular/skills"
    Write-Host "    .NET:    https://github.com/dotnet/skills"
    Write-Host ""
    if ($HasOpenCode) {
        Write-Info "OpenCode: Start a new session and use /angular-developer or /dotnet-developer"
    }
    if ($HasClaude) {
        Write-Info "Claude:   Start a new session - skills load automatically from .claude/skills/"
    }

} finally {
    # Cleanup temp directory
    if (Test-Path $CacheDir) {
        Remove-Item -Path $CacheDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
