# KGSM AI Coding Agent Instructions

> **Note**: General bash coding standards are defined in `.github/instructions/copilot.md`.
> This document covers KGSM-specific architecture and patterns.

## Commands

### Testing
```bash
# Run all tests
./tests/run.sh

# Run a specific test type
./tests/run.sh unit
./tests/run.sh integration
./tests/run.sh e2e

# Run tests matching a pattern (filename glob)
./tests/run.sh --pattern 'test_config_*.sh'

# Run a specific test function within a file
./tests/run.sh --pattern 'test_config_merge_logic.sh' --function 'test_merge_preserves_user_values'
```

### Linting
```bash
shellcheck path/to/script.sh
```

### Running KGSM
```bash
./kgsm.sh --help
./kgsm.sh --debug [command]   # Enable debug/trace output
```

## Project Overview

**KGSM (Krystal Game Server Manager)** is a bash-based game server orchestration system for Linux. It uses a **blueprint-based architecture** to deploy, manage, and maintain diverse game servers through a unified interface—supporting both native Linux servers and Docker containers.

## Core Architecture Concepts

### 1. Blueprint → Instance → Override Pattern

The system follows a three-tier architecture:

- **Blueprints** (`blueprints/*/native/*.bp`, `blueprints/*/container/*.docker-compose.yml`): Configuration templates defining server parameters (ports, executable paths, Steam app IDs)
- **Instances** (`instances/*/`): Deployed game servers created from blueprints, each with isolated directories and management scripts
- **Overrides** (`overrides/*.overrides.sh`): Game-specific function implementations that customize installation/update/lifecycle behavior

**Critical**: Blueprints link to overrides via the `name=` field **not** the filename. Example: `terraria-modded.bp` with `name=terraria` uses `terraria.overrides.sh`. This enables multiple blueprint variants to share logic while reducing code duplication.

### 2. Module Loading System

KGSM uses a sophisticated bootstrap and loader system (`core/bootstrap.sh`, `core/loader.sh`):

- **KGSM_ROOT**: Auto-detected root directory, exported globally
- **Module discovery**: `__find_command()`, `__find_core_module()`, `__find_or_fail()` functions locate files dynamically
- **Lazy loading**: Modules loaded on-demand with guards (`if [[ ! $KGSM_COMMON_LOADED ]]`)
- **Environment isolation**: Debug mode (`--debug` flag or `KGSM_DEBUG=true`) propagates to all sub-shells
- **Function exports**: All library functions must use `export -f function_name` for subprocess availability

All modules must source `core/bootstrap.sh` first, which establishes the environment and loads `core/common.sh`.

**Command/Handler Pattern**: User-facing commands (`commands/*.sh`) delegate to pure logic handlers (`commands/handlers/*.sh`). Commands handle I/O, error messages, and CLI argument parsing; handlers contain pure business logic with no I/O, returning only exit codes. This separation enables testability and code reuse.

### 3. Error Code System

Standardized exit codes (`core/errors.sh`) enable precise error handling:
- `EC_OKAY=0`, `EC_GENERAL=1`, `EC_FILE_NOT_FOUND=5`, `EC_BLUEPRINT_NOT_FOUND=27`, etc.
- **Always use numeric exit codes unquoted** (shellcheck SC2086 disabled globally)
- User-facing modules should print errors AND return exit codes

### 4. Configuration Management

Advanced config system with schema versioning and automatic migrations:

**Structure**:
- **Sectioned INI format**: Config organized into logical sections:
  - `[system]`: Core paths, logging, shell settings
  - `[network]`: Firewall, port forwarding, timeouts
  - `[steam]`: Steam-specific authentication and settings
  - `[services]`: systemd integration settings
  - `[instance_defaults]`: Default values for new instances
  - `[events]`: Webhook and socket notification settings
  - `[watchers]`: Log and port monitoring configuration
  - `[accessibility]`: Colors and interactive features
- **Schema versioning**: `config_schema_version=1` tracks format changes
- **Flat exports**: Variables still exported as `config_*` for backward compatibility

**Merge System** (`core/config.sh`):
- `__merge_user_config_with_default()`: Main merge orchestrator
- `__create_config_backup()`: Numbered backups (.0 through .9, 10 generations)
- `__run_config_migrations()`: Executes sequential migrations from `migrations/config/`
- `__parse_config_to_map()`: INI parser into associative arrays
- `__handle_deprecated_keys()`: Comments out obsolete keys with warnings

**Migration Framework** (`migrations/config/`):
- Sequential numbered scripts (001, 002, 003...)
- Auto-run during updates when schema version changes
- Idempotent (safe to run multiple times)
- Create `.pre-migration-vX.bak` backups

**CLI Commands** (`commands/config.sh`):
- `./kgsm.sh config merge` - Manual merge with defaults
- `./kgsm.sh config rollback [0-9]` - Restore from backup
- `./kgsm.sh config diff [0-9]` - Show changes from backup
- `./kgsm.sh config validate` - Check integrity

**Auto-Update Integration** (`installer.sh`):
- Config automatically merged after `./installer.sh --update`
- Preserves user customizations while adding new keys
- Handles deprecated keys gracefully

**Error Codes**:
- `EC_SUCCESS_CONFIG_MERGED=243`, `EC_MIGRATION_FAILED=245`, `EC_MIGRATION_NOT_FOUND=246`
- `EC_MISSING_CONFIG_KEY=247`, `EC_INVALID_CONFIG_VALUE=248`, `EC_FAILED_BACKUP=249`

## File Structure Conventions

```
kgsm.sh                    # Main entry point, delegates to modules
core/
  bootstrap.sh             # Environment setup, KGSM_ROOT detection
  loader.sh                # File discovery functions, path constants
  common.sh                # Loads all essential libraries
  delegator.sh             # Dynamic wrapper generation for commands
  config.sh                # Config parsing, merging, validation
  errors.sh                # Exit code constants (EC_*)
  events.sh                # Event dispatching system
  logging.sh               # Logging functions (__print_error, __print_info)
  overrides.sh             # Override loading and sourcing
  parser.sh                # Blueprint and INI parsing
  validation.sh            # Input validation functions
commands/                  # User-facing command handlers (I/O layer)
  blueprints.sh            # Blueprint CLI (list, info, find)
  instances.sh             # Instance management CLI
  lifecycle.sh             # Start/stop/restart commands
  config.sh                # Config merge/rollback/diff/validate
  handlers/                # Pure business logic (no I/O)
    blueprints.sh          # Blueprint validation/processing logic
    instances.sh           # Instance creation/removal logic
    lifecycle.sh           # Lifecycle state management logic
overrides/                 # Game-specific implementations
  factorio.overrides.sh    # Custom functions for Factorio
  terraria.overrides.sh    # Custom functions for Terraria
templates/                 # File generation templates
  blueprint.tp             # Blueprint template
  manage.native.tp         # Instance management script template
  overrides.tp             # Override template with full API docs
blueprints/               # Server configuration templates
  native/                 # Native Linux servers
    default/              # Bundled blueprints
    custom/               # User-created blueprints
  container/              # Docker-based servers
instances/                # Deployed server instances
migrations/               # Config schema migration scripts
  config/                 # Sequential migration files (001_*, 002_*)
tests/
  run.sh                  # Main entry point and test runner
  framework/              # Test infrastructure
    assert.sh             # Assertion library
    sandbox.sh            # Isolated test environments
  unit/                   # Module-level tests
  integration/            # Cross-module tests
  e2e/                    # Full workflow tests (real game servers)
```

## Critical Development Patterns

### Override Function Signatures

When implementing overrides, follow signatures from `templates/overrides.tp`:

```bash
# Version checking (must echo version or exit 1)
function _get_latest_version() {
  # Return: echo "1.2.3" OR exit 1
}

# Download (receives version, uses $instance_temp_dir)
function _download() {
  local version=$1
  local dest=$instance_temp_dir
  # Return: exit 0 on success, exit 1 on failure
}

# Deploy (moves from temp to install directory)
function _deploy() {
  # Return: exit 0 on success, exit 1 on failure
}
```

**Available instance variables**: `instance_name`, `instance_install_dir`, `instance_temp_dir`, `instance_working_dir`, `instance_saves_dir`, `instance_backups_dir`, `instance_logs_dir`, `instance_executable_file`, `instance_ports`, etc. (see `templates/overrides.tp` for complete list).

### Blueprint Field Requirements

**Required fields**:
- `name`: Unique identifier (lowercase, no spaces)
- `executable_file`: Server binary name
- `level_name`: Default world/map name

**Optional but common**:
- `ports`: Format `'1111:2222/tcp|3333/udp'` (single-quoted, pipe-separated)
- `steam_app_id`: For Steam-based servers
- `client_steam_app_id`: Client Steam App ID for launch/connect (`0` if not Steam)
- `executable_subdirectory`: Relative path if binary is nested
- `executable_arguments`: Command-line args for server startup

### Testing Framework Integration

**The `@testing` agent is the gatekeeper for ALL testing framework interactions.** Any work involving the testing framework — reading tests, writing tests, modifying tests, understanding framework internals, or debugging test failures — MUST be delegated to the `@testing` agent.

**When to delegate to `@testing`:**
- Creating or modifying any file in `tests/`
- Reading or interpreting testing documentation (`docs/specs/testing-framework/`)
- Writing test functions, assertions, setup/teardown hooks
- Debugging test failures or understanding test output
- Any question about test conventions, naming, structure, or assertions
- Adding tests as part of a feature implementation

**How to delegate:**
- If you are an agent: invoke `@testing` as a subagent with a detailed prompt describing what needs to be tested, including the module name, expected behavior, and any relevant context you've gathered
- Do NOT write test code yourself — `@testing` owns the framework and knows its conventions

**What `@testing` manages:**
- Test framework modules (`tests/framework/*.sh`)
- Test files (`tests/unit/`, `tests/integration/`, `tests/e2e/`)
- Test documentation (`docs/specs/testing-framework/`, `tests/README.md`)
- Test template (`tests/templates/test.template.sh`)
- Test configuration (`tests/config.test.ini`)
- TAP v14 output format and VS Code Test Adapter integration

**Quick reference (for understanding, not for writing tests yourself):**
- Tests run in sandboxed KGSM copies (`/tmp/kgsm-test-sandbox-*/`)
- No mocking — tests execute real KGSM code
- Run tests: `./tests/run.sh` or `./tests/run.sh --pattern 'my_new_module'`

### Behavioral Uncertainty Principle

**Never write code with uncertain outcomes**. See `docs/behavioral_uncertainty_quick_reference.md`:
- ❌ Commands that "may succeed or fail depending on implementation"
- ✅ Commands with **defined, testable behavior**
- When encountering uncertain patterns, document expected behavior first, then implement consistently

Example: ID generation should either ALWAYS validate blueprints or NEVER validate—not sometimes.

## Common Development Tasks

### Adding a New Game Server

1. **Create blueprint**: Copy `templates/blueprint.tp` to `blueprints/custom/native/yourgame.bp`
2. **Fill required fields**: Set `name`, `ports`, `steam_app_id` (if applicable), `executable_file`, `level_name`
3. **Test basic creation**: `./kgsm.sh --create yourgame --name test --install-dir /tmp/test-server`
4. **Create override** (if needed): Copy `templates/overrides.tp` to `overrides/yourgame.overrides.sh`
5. **Implement custom functions**: Override `_get_latest_version()`, `_download()`, `_deploy()` as needed
6. **Add tests**: Create `tests/integration/test_yourgame_integration.sh`

### Adding a Configuration Migration

1. **Create migration script**: `migrations/config/00X_description.sh`
2. **Implement migration**: Check schema version, migrate keys, update version
3. **Test migration**: Create `tests/unit/test_config_migrations.sh` test case
4. **Verify idempotency**: Ensure running twice doesn't break config
5. **Update schema version**: Increment in `config.default.ini`

### Modifying Module Behavior

1. **Check module type**: User-facing (`commands/`) or library (`core/`)?
2. **Source bootstrap**: All modules must `source core/bootstrap.sh` first
3. **Use exit codes**: Return `EC_*` constants, not magic numbers
4. **Export functions**: Use `export -f function_name` for functions called by subprocesses
5. **Add usage function**: All user-facing modules need `function usage()`

### Debugging Issues

1. **Enable debug mode**: `./kgsm.sh --debug [command]` or `export KGSM_DEBUG=true`
2. **Check logs**: `logs/` directory contains operation logs (if `config_enable_logging=true`)
3. **Test sandbox**: `./tests/run.sh --debug --pattern 'test_specific.sh'` runs tests with full trace
4. **Validate config**: `./kgsm.sh config validate` checks configuration integrity
5. **Config troubleshooting**: 
   - `./kgsm.sh config diff 0` - See recent changes
   - `./kgsm.sh config rollback 0` - Undo last change
   - Check `.pre-migration-vX.bak` files if migration issues occur

## Code Style & Conventions

- **Shellcheck compliance**: All code must pass shellcheck (globally disabled: SC2086 for exit codes)
- **Function naming**: Private functions use `_function_name()`, library helpers use `__function_name()`
- **Variable prefixes**: Config vars = `config_*`, instance vars = `instance_*`, internal = `_var`
- **Quoting**: Always quote user input variables; exit codes unquoted
- **Error messages**: Use `__print_error`, `__print_warning`, `__print_info` from common library

## Key Files for Reference

- **Architecture docs**: `docs/execution_flows.md`, `docs/blueprints.md`, `docs/overrides.md`, `docs/instances.md`
- **Config management**: `docs/configuration_management.md` (user guide), `docs/config_management_specification.md` (technical spec)
- **API reference**: `templates/overrides.tp` (complete override function documentation)
- **Testing specification**: `docs/testing_specification.md` (**REQUIRED** reference for all test creation/modification)
- **Testing guide**: `docs/testing_framework.md`, `tests/README.md`
- **Example overrides**: `overrides/factorio.overrides.sh`, `overrides/terraria.overrides.sh`
- **Example blueprints**: `blueprints/default/native/factorio.bp`, `blueprints/default/native/minecraft.bp`
- **Example migration**: `migrations/config/001_v0_to_v1_flat_to_sectioned.sh` (flat to sectioned format)

## Integration Points

- **systemd**: Optional service file generation (`templates/service.tp`)
- **UFW firewall**: Automatic port rule creation (if `config_enable_firewall_management=true`)
- **Event system**: Webhooks and socket-based notifications (`commands/events.*.sh`)

---

**When in doubt**: Check existing implementations in `blueprints/default/native/`, `overrides/`, and corresponding tests in `tests/`. The codebase is self-documenting through extensive examples.
