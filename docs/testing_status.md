# KGSM Testing Status Tracker

**Version:** 1.0  
**Last Updated:** December 8, 2025  
**Purpose:** Track testing progress for all KGSM command modules

---

## Overview

This document tracks the testing status of all KGSM command modules as they transition from legacy argument-based architecture to modern command-based architecture with separated logic/I/O layers.

### Testing Levels

Each module can have the following test coverage:

1. **Logic Tests** - Test pure `__logic_*` functions from `commands/handlers/*.sh`
2. **Command Tests** - Test command-based CLI from `commands/*.sh`
3. **Integration Tests** - Test module interactions with other modules
4. **E2E Tests** - Test complete workflows involving the module

### Status Definitions

- ❌ **No Tests** - No tests exist for this component
- 🟡 **Partial** - Some tests exist but incomplete coverage
- ✅ **Complete** - Comprehensive test coverage with all scenarios

---

## Module Testing Status Matrix

### Core Modules (High Priority)

These modules are fundamental to KGSM operation and should be tested first.

| Module           | Has Handler   | Logic Tests | Command Tests | Integration Tests | E2E Tests | Priority   | Notes                                         |
| ---------------- | ------------- | ----------- | ------------- | ----------------- | --------- | ---------- | --------------------------------------------- |
| `blueprints.sh`  | ✅             | ✅           | ❌             | ❌                 | ❌         | 🔴 **HIGH** | Core functionality - blueprint management     |
| `instances.sh`   | ✅             | ❌           | ❌             | ❌                 | ❌         | 🔴 **HIGH** | Core functionality - instance management      |
| `lifecycle.sh`   | ✅             | ❌           | ❌             | ❌                 | ❌         | 🔴 **HIGH** | Core functionality - start/stop/restart       |
| `directories.sh` | ✅             | ✅           | ❌             | ❌                 | ❌         | 🔴 **HIGH** | Core functionality - directory structure      |
| `config.sh`      | ✅ (uses core) | ❌           | ❌             | ❌                 | ❌         | 🔴 **HIGH** | Core functionality - configuration management |

### File Management Modules (Medium Priority)

These modules handle file operations and system integration.

| Module                | Has Handler | Logic Tests | Command Tests | Integration Tests | E2E Tests | Priority     | Notes                                  |
| --------------------- | ----------- | ----------- | ------------- | ----------------- | --------- | ------------ | -------------------------------------- |
| `files.sh`            | ❌           | N/A         | ❌             | ❌                 | ❌         | 🟡 **MEDIUM** | Orchestrator - delegates to submodules |
| `files.config.sh`     | ✅           | ❌           | ❌             | ❌                 | ❌         | 🟡 **MEDIUM** | Config file installation               |
| `files.management.sh` | ✅           | ❌           | ❌             | ❌                 | ❌         | 🟡 **MEDIUM** | Management script generation           |
| `files.systemd.sh`    | ✅           | ❌           | ❌             | ❌                 | ❌         | 🟡 **MEDIUM** | Systemd service file operations        |
| `files.symlink.sh`    | ✅           | ❌           | ❌             | ❌                 | ❌         | 🟡 **MEDIUM** | Symlink management                     |
| `files.ufw.sh`        | ✅           | ❌           | ❌             | ❌                 | ❌         | 🟡 **MEDIUM** | UFW firewall rules                     |
| `files.upnp.sh`       | ✅           | ❌           | ❌             | ❌                 | ❌         | 🟡 **MEDIUM** | UPnP port forwarding                   |

### System Integration Modules (Medium Priority)

These modules integrate with system services and network features.

| Module              | Has Handler | Logic Tests | Command Tests | Integration Tests | E2E Tests | Priority     | Notes                                |
| ------------------- | ----------- | ----------- | ------------- | ----------------- | --------- | ------------ | ------------------------------------ |
| `network.sh`        | ✅           | ❌           | ❌             | ❌                 | ❌         | 🟡 **MEDIUM** | Network operations and port checking |
| `system.sh`         | ✅           | ❌           | ❌             | ❌                 | ❌         | 🟡 **MEDIUM** | System information and operations    |
| `events.sh`         | ✅           | ✅           | ❌             | ❌                 | ❌         | 🟡 **MEDIUM** | Event system orchestration           |
| `events.socket.sh`  | ❌           | N/A         | ❌             | ❌                 | ❌         | 🟢 **LOW**    | Specialized - socket transport       |
| `events.webhook.sh` | ❌           | N/A         | ❌             | ❌                 | ❌         | 🟢 **LOW**    | Specialized - webhook transport      |

### Monitoring & Automation Modules (Low Priority)

These modules provide monitoring and automation features.

| Module             | Has Handler | Logic Tests | Command Tests | Integration Tests | E2E Tests | Priority  | Notes                       |
| ------------------ | ----------- | ----------- | ------------- | ----------------- | --------- | --------- | --------------------------- |
| `watcher.sh`       | ✅           | ❌           | ❌             | ❌                 | ❌         | 🟢 **LOW** | Watcher orchestration       |
| `watcher.logs.sh`  | ❌           | N/A         | ❌             | ❌                 | ❌         | 🟢 **LOW** | Specialized - log watching  |
| `watcher.ports.sh` | ❌           | N/A         | ❌             | ❌                 | ❌         | 🟢 **LOW** | Specialized - port watching |

### Specialized & Utility Modules

These modules have specialized purposes or are utilities.

| Module                    | Has Handler | Logic Tests | Command Tests | Integration Tests | E2E Tests | Priority     | Notes                                          |
| ------------------------- | ----------- | ----------- | ------------- | ----------------- | --------- | ------------ | ---------------------------------------------- |
| `blueprints.native.sh`    | ❌           | N/A         | ❌             | ❌                 | ❌         | 🟡 **MEDIUM** | Specialized submodule for native blueprints    |
| `blueprints.container.sh` | ❌           | N/A         | ❌             | ❌                 | ❌         | 🟡 **MEDIUM** | Specialized submodule for container blueprints |
| `install.sh`              | ❌           | N/A         | ❌             | ❌                 | ❌         | 🟢 **LOW**    | Installation utility                           |
| `uninstall.sh`            | ❌           | N/A         | ❌             | ❌                 | ❌         | 🟢 **LOW**    | Uninstallation utility                         |
| `interactive.sh`          | ❌           | N/A         | N/A           | N/A               | N/A       | ⚪ **MANUAL** | Interactive wizard - manual testing only       |

---

## Testing Progress Summary

### Overall Statistics

- **Total Modules:** 25
- **Modules with Handlers:** 16
- **Modules Tested:** 3
- **Modules Untested:** 22
- **Manual Testing Only:** 1 (`interactive.sh`)

### Coverage by Test Type

| Test Type         | Modules with Coverage | Percentage |
| ----------------- | --------------------- | ---------- |
| Logic Tests       | 3 / 16                | 18.75%     |
| Command Tests     | 0 / 25                | 0%         |
| Integration Tests | 0 / 25                | 0%         |
| E2E Tests         | 0 / 25                | 0%         |

### Progress by Priority

| Priority     | Total Modules | Tested | Untested |
| ------------ | ------------- | ------ | -------- |
| 🔴 **HIGH**   | 5             | 2      | 3        |
| 🟡 **MEDIUM** | 13            | 1      | 12       |
| 🟢 **LOW**    | 6             | 0      | 6        |
| ⚪ **MANUAL** | 1             | 0      | 1        |

---

## Testing Roadmap

### Phase 1: Core Modules (HIGH Priority)

**Goal:** Establish comprehensive testing for fundamental KGSM operations

**Target Modules:**
1. `blueprints.sh` + `handlers/blueprints.sh`
   - Logic tests for blueprint validation, type detection, path resolution
   - Command tests for list, info, find commands
   - Integration tests with instances module

2. `instances.sh` + `handlers/instances.sh`
   - Logic tests for instance creation, removal, ID generation
   - Command tests for create, remove, list, info commands
   - Integration tests with directories and files modules

3. `lifecycle.sh` + `handlers/lifecycle.sh`
   - Logic tests for start, stop, restart operations
   - Command tests for all lifecycle commands
   - Integration tests with systemd (if enabled)

4. `directories.sh` + `handlers/directories.sh`
   - Logic tests for directory creation/removal
   - Command tests for create, remove commands
   - Integration tests with instances module

5. `config.sh` + `core/config.sh`
   - Logic tests for config get/set/reset operations
   - Command tests for all config commands
   - Integration tests with other modules that use config

**Estimated Effort:** 3-4 weeks  
**Success Criteria:** All core modules have ✅ Complete status

### Phase 2: File Management Modules (MEDIUM Priority)

**Goal:** Test file generation and system integration

**Target Modules:**
- All `files.*.sh` modules and their handlers
- Focus on integration between file modules and instances

**Estimated Effort:** 2-3 weeks  
**Success Criteria:** All file modules have ✅ Complete status

### Phase 3: System Integration (MEDIUM Priority)

**Goal:** Test system service integration and networking

**Target Modules:**
- `network.sh`, `system.sh`, `events.sh`
- Specialized event transports

**Estimated Effort:** 2 weeks  
**Success Criteria:** All system modules have ✅ Complete status

### Phase 4: Monitoring & Specialized (LOW Priority)

**Goal:** Test remaining modules and specialized functionality

**Target Modules:**
- Watcher modules
- Specialized submodules
- Utilities

**Estimated Effort:** 1-2 weeks  
**Success Criteria:** All remaining modules have appropriate test coverage

---

## Test Creation Workflow

For each module, follow this workflow:

### Step 1: Logic Layer Tests (if module has handler)

1. Copy `tests/templates/logic_test.template.sh` to `tests/unit/test_<module>_logic.sh`
2. Replace template placeholders with module-specific values
3. Implement test functions for each `__logic_*` function
4. Test all success cases, error cases, and edge cases
5. Run tests: `./tests/run.sh --pattern <module>_logic`
6. Update this document: Change Logic Tests from ❌ to ✅

### Step 2: Command Layer Tests

1. Copy `tests/templates/command_test.template.sh` to `tests/unit/test_<module>_commands.sh`
2. Replace template placeholders with module-specific values
3. Implement tests for help system, each command, error handling
4. Test argument parsing, output messages, exit codes
5. Run tests: `./tests/run.sh --pattern <module>_commands`
6. Update this document: Change Command Tests from ❌ to ✅

### Step 3: Integration Tests

1. Identify modules that interact with this module
2. Copy `tests/templates/integration_test.template.sh` to `tests/integration/test_<module1>_<module2>_integration.sh`
3. Implement tests for module interaction workflows
4. Test data flow, state consistency, error propagation
5. Run tests: `./tests/run.sh integration`
6. Update this document: Change Integration Tests from ❌ to ✅

### Step 4: E2E Tests

1. Identify complete user workflows involving this module
2. Copy `tests/templates/e2e_test.template.sh` to `tests/e2e/test_<workflow>_e2e.sh`
3. Implement tests for realistic scenarios
4. May require external dependencies (SteamCMD, Docker)
5. Run tests: `./tests/run.sh e2e`
6. Update this document: Change E2E Tests from ❌ to ✅

---

## Testing Guidelines

### When to Update This Document

Update this document whenever:
- ✅ A new test file is created
- ✅ Test coverage is significantly improved
- ✅ A module reaches "Complete" status
- ✅ New modules are added to KGSM
- ✅ Testing priorities change

### Status Update Criteria

**❌ No Tests → 🟡 Partial:**
- At least one test file exists
- Basic success cases are tested
- Some error cases are tested

**🟡 Partial → ✅ Complete:**
- All public functions/commands are tested
- Success cases, error cases, and edge cases covered
- Integration with related modules tested
- Code coverage > 80% (if measured)
- All tests pass consistently

### Testing Best Practices

1. **Follow templates** - Use provided templates for consistency
2. **Test behavioral certainty** - Every test should have defined outcomes
3. **Use framework utilities** - Leverage `create_test_instance`, `wait_for_port`, etc.
4. **Clean up resources** - Always remove test instances and files
5. **Document test purpose** - Use `log_step` to explain what each test does
6. **Test error paths** - Don't just test success cases
7. **Run tests locally** - Before committing, run `./tests/run.sh`

---

## Notes & Considerations

### Modules Without Handlers

Some modules don't have handler files because they:
- Are orchestrators that delegate to other modules (`files.sh`, `events.sh`)
- Are specialized submodules with specific purposes
- Are utilities with different architectural patterns

**Testing Approach:**
- Focus on command-level testing
- Test integration with modules they orchestrate
- May not need separate logic layer tests

### Interactive Module

`interactive.sh` is a 2349-line menu-driven wizard that requires **manual testing only**:
- Cannot be effectively automated due to interactive prompts
- Should be tested manually for each release
- Consider creating a separate manual testing checklist

### External Dependencies

Some tests require external tools:
- **SteamCMD** - For game server download/update tests
- **Docker** - For container-based blueprint tests
- **systemd** - For service integration tests
- **UFW** - For firewall rule tests

**Handling:**
- Use `require_steamcmd()`, `require_docker()` to skip when unavailable
- Document required dependencies in test files
- Consider separate test categories for dependency-heavy tests

### Container vs Native Blueprints

Both `blueprints.native.sh` and `blueprints.container.sh` need testing:
- Test native blueprints with `.bp` files
- Test container blueprints with `docker-compose.yml`
- Both should work through main `blueprints.sh` interface

---

## Changelog

### 2025-12-09
- **[Update]** Events logic tests completed (✅) - 45 tests, 71 assertions covering `__logic_validate_event_type`, `__logic_validate_event_params`, `__logic_get_event_param_spec`, `__logic_event_name_to_type`
- **[Update]** Updated coverage statistics: 3/16 logic tests complete (18.75%)
- **[Update]** Updated priority statistics: 1/13 MEDIUM priority modules tested
- **[Update]** Directories logic tests completed (✅) - 26 tests covering `__create_dir`, `__create_file`, `__logic_create_directories`, `__logic_remove_directories`
- **[Update]** Updated coverage statistics: 2/16 logic tests complete (12.5%)
- **[Update]** Updated priority statistics: 2/5 HIGH priority modules tested

### 2025-12-08
- **[Initial]** Created testing status tracker
- **[Initial]** All modules marked as untested
- **[Initial]** Defined testing roadmap with 4 phases
- **[Initial]** Established testing workflow and update criteria
- **[Update]** Blueprints logic tests completed (✅) - 133 assertions covering all `__logic_*` functions
- **[Update]** Updated coverage statistics: 1/16 logic tests complete (6.25%)
- **[Update]** Updated priority statistics: 1/5 HIGH priority modules tested

---

**For questions or updates, refer to:**
- Testing Specification: `docs/testing_specification.md`
- Testing Framework: `docs/testing_framework.md`
- Test Templates: `tests/templates/`
