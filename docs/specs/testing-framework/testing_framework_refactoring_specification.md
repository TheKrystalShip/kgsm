# KGSM Testing Framework Refactoring Specification

**Version:** 1.0  
**Date:** December 17, 2025  
**Status:** Planning  
**Author:** KGSM Development Team

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current Architecture Problems](#2-current-architecture-problems)
3. [KGSM Core Architecture Reference](#3-kgsm-core-architecture-reference)
4. [Proposed Architecture](#4-proposed-architecture)
5. [Module Responsibilities](#5-module-responsibilities)
6. [Dependency Graph](#6-dependency-graph)
7. [Execution Flow](#7-execution-flow)
8. [Migration Strategy](#8-migration-strategy)
9. [Success Criteria](#9-success-criteria)
10. [Next Steps](#10-next-steps)

---

## 1. Executive Summary

### 1.1 Purpose

The KGSM testing framework has grown organically but lacks the architectural consistency found in KGSM core. This refactoring aligns the test framework with KGSM's proven patterns: **bootstrap → loader → common → specialized modules**.

### 1.2 Core Problems

| Problem Category           | Description                                                                | Impact                                                 |
| -------------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------ |
| **No Bootstrap Pattern**   | Environment setup scattered across 3 files                                 | Unclear initialization, multiple KGSM_ROOT definitions |
| **Module Coupling**        | `common.sh` does everything (orchestration + utilities + KGSM integration) | Hard to test, modify, or understand                    |
| **Code Duplication**       | Color constants defined 5 times, logging functions in 3 places             | Maintenance burden, inconsistencies                    |
| **Mixed Responsibilities** | `runner.sh` handles sandbox + execution + reporting + config (665 lines)   | Single-file does 6+ distinct jobs                      |
| **No Abstraction Layer**   | KGSM-specific logic mixed throughout framework                             | Can't reuse framework, can't test framework itself     |

### 1.3 Desired End State

```
Clear Separation          →  bootstrap.sh (init) → loader.sh (constants) → common.sh (orchestrator) → specialized modules
Single Responsibility     →  Each module has exactly ONE job
Consistent Patterns       →  All modules follow KGSM core patterns (load guards, exports, no duplication)
Testable Architecture     →  Framework modules can be tested independently
KGSM Abstraction         →  KGSM-specific logic isolated to kgsm.sh integration layer
```

### 1.4 Success Criteria

**Quantitative:**
- Reduce `runner.sh` from 665 lines to <200 lines
- Reduce `common.sh` responsibilities from 8 to 1 (orchestration only)
- Eliminate 4 duplicate color constant definitions
- Create 11 focused modules averaging <250 lines each

**Qualitative:**
- Any developer can understand module purpose in <5 minutes
- New test types can be added without modifying core framework
- Framework bugs can be isolated to specific modules
- Test creation workflow remains simple and fast

---

## 2. Current Architecture Problems

### 2.1 File Structure Overview

**Current files and their issues:**

| File          | Lines | Issues                                                       | Root Cause                   |
| ------------- | ----- | ------------------------------------------------------------ | ---------------------------- |
| `run.sh`      | 295   | Duplicates validation, defines own colors, redundant wrapper | No clear entry point pattern |
| `runner.sh`   | 665   | 6+ responsibilities mixed together                           | No module separation         |
| `common.sh`   | ~500  | "Common" actually means "everything"                         | No clear contract            |
| `logging.sh`  | 327   | Good separation BUT duplicates color constants               | No single source of truth    |
| `assert.sh`   | 806   | Good separation BUT redefines exit codes and colors          | No single source of truth    |
| `fixtures.sh` | 243   | ✅ Well-structured (keep as-is)                               | N/A                          |

### 2.2 Key Architectural Issues

#### 2.2.1 No Bootstrap Pattern

**Problem:**
```
run.sh:         Sets KGSM_ROOT = $(cd "$TESTS_ROOT/.." && pwd)
runner.sh:      Sets KGSM_ROOT = $(cd "$TESTS_ROOT/.." && pwd)  [DUPLICATE]
bootstrap.sh:   Sets KGSM_ROOT conditionally                     [AGAIN]
Test sandbox:   Sets KGSM_ROOT = $sandbox_path                   [CONTEXT SWITCH]
```

**Impact:** KGSM_ROOT changes meaning mid-execution (host → sandbox → host), causing confusion about which KGSM installation is active.

**Solution:** Single bootstrap module that detects `TEST_ROOT` and `KGSM_ROOT` exactly once, never modified afterward.

#### 2.2.2 Module Coupling Chaos

**Problem:** Dependency chain is unclear and tangled:
```
run.sh → runner.sh → common.sh → [bootstrap, logging, assert, fixtures] + KGSM core
                                   ↑
                        Circular? Who loads what first?
```

**Impact:** Can't test modules in isolation, can't load framework partially, fragile to changes.

**Solution:** Linear dependency chain: `bootstrap → loader → common → [specialized modules]` where each module is independent.

#### 2.2.3 Scattered Responsibilities

**Current `runner.sh` does:**
1. Configuration management (`load_test_config`)
2. Sandbox lifecycle (`create_sandbox`, `cleanup_sandbox`)
3. Test discovery (`discover_tests`, `should_run_test`)
4. Test execution (`execute_test`)
5. Logging (`log_message`, `print_*`)
6. Reporting (`generate_summary`)
7. Argument parsing
8. Main orchestration

**Impact:** 665-line file that's hard to navigate, test, or modify. Changes to logging affect sandbox creation.

**Solution:** Extract each responsibility into dedicated module.

#### 2.2.4 Duplication Everywhere

**Color Constants:**
```bash
run.sh:18        → RED, GREEN, YELLOW, BLUE, CYAN, WHITE, GRAY, NC, BOLD
runner.sh        → [inherits from common.sh]
logging.sh:40    → KGSM_LOG_RED, KGSM_LOG_GREEN, ... (different names!)
assert.sh:28     → RED, GREEN, YELLOW, ... (redefined AGAIN)
common.sh:51     → RED, GREEN, YELLOW, ... (and AGAIN)
```

**Impact:** 5 definitions = 5 places to update when adding new colors, inconsistent naming.

**Solution:** Define once in `loader.sh`, export with consistent names (`TEST_COLOR_*`).

**Exit Codes:**
```bash
assert.sh:19     → ASSERT_SUCCESS, ASSERT_FAILURE
common.sh:47     → EC_SUCCESS, EC_FAILURE, EC_SKIP, EC_ERROR
KGSM errors.sh   → Full EC_* suite (canonical)
```

**Impact:** Unclear which exit codes are authoritative, potential conflicts.

**Solution:** Use KGSM core's `errors.sh` for all exit codes, no redefinitions.

### 2.3 Environment Management Problems

#### 2.3.1 KGSM_ROOT Juggling

**Execution trace:**
```
1. run.sh sets KGSM_ROOT=/home/user/kgsm (host)
2. runner.sh sets KGSM_ROOT=/home/user/kgsm (redundant)
3. runner.sh sources common.sh
4. common.sh sources bootstrap.sh
5. bootstrap.sh sets KGSM_ROOT=/home/user/kgsm (again!)
6. Test starts: runner.sh changes KGSM_ROOT=/tmp/sandbox/... (context switch)
7. Test ends: runner.sh restores KGSM_ROOT=/home/user/kgsm (restore)
```

**Problem:** Functions that cache `$KGSM_ROOT` reference wrong location after context switch.

**Solution:** Separate `TEST_ROOT` (host framework) from `KGSM_ROOT` (test target). Never modify after initialization.

#### 2.3.2 Test Context Scattered

**Current approach:** Environment variables everywhere:
```bash
KGSM_TEST_MODE=true
KGSM_TEST_LOG=/path/to/log
KGSM_TEST_SANDBOX=/tmp/sandbox
KGSM_TEST_LOG_LEVEL=INFO
KGSM_LOG_CONSOLE_ENABLED=false
```

**Problem:** No single source of truth for test context, easy to miss setting a variable.

**Solution:** All test context managed by framework modules, exported consistently.

---

## 3. KGSM Core Architecture Reference

### 3.1 The Proven Pattern

KGSM core uses a three-tier initialization pattern that works flawlessly:

```
bootstrap.sh (58 lines)    →  Environment detection and minimal setup
    ↓
loader.sh (423 lines)      →  Path constants and file discovery helpers
    ↓
common.sh (100 lines)      →  Orchestration: loads all other modules
    ↓
[Specialized Modules]      →  errors, config, logging, parser, validation, etc.
```

### 3.2 Key Principles

| Principle                 | Implementation                                    | Benefit                       |
| ------------------------- | ------------------------------------------------- | ----------------------------- |
| **Single Initialization** | Only `bootstrap.sh` detects KGSM_ROOT             | No redundancy, no conflicts   |
| **Load Guards**           | `if [[ -n "$MODULE_LOADED" ]]; then return 0; fi` | Safe to source multiple times |
| **Clear Separation**      | Bootstrap ≠ Loader ≠ Common ≠ Modules             | Each has one job              |
| **No Duplication**        | Constants defined once, exported                  | Single source of truth        |
| **Consistent Export**     | All modules end with `export MODULE_LOADED=1`     | Easy to check what's loaded   |

### 3.3 Module Structure Template

Every KGSM core module follows this pattern:

```bash
#!/usr/bin/env bash

# Load guard
if [[ -n "${MODULE_NAME_LOADED:-}" ]]; then
  return 0
fi

# Module code here
# - Function definitions
# - Variable exports
# - Logic implementation

# Mark as loaded
export MODULE_NAME_LOADED=1
```

### 3.4 Why This Works

1. **Predictable:** Always loads in same order
2. **Debuggable:** Check `$MODULE_NAME_LOADED` to see what's active
3. **Testable:** Each module can be sourced independently
4. **Maintainable:** Clear boundaries prevent feature creep
5. **Extensible:** Add new modules without touching existing ones

---

## 4. Proposed Architecture

### 4.1 New Structure

```
tests/
├── run.sh                           # Entry point: validation, exec runner.sh
├── framework/
│   ├── bootstrap.sh                 # 🆕 Environment initialization
│   ├── loader.sh                    # 🆕 Constants and helpers
│   ├── common.sh                    # ♻️  Orchestrator ONLY
│   ├── config.sh                    # 🆕 Test configuration
│   ├── sandbox.sh                   # 🆕 Sandbox lifecycle
│   ├── discovery.sh                 # 🆕 Test discovery
│   ├── execution.sh                 # 🆕 Test execution
│   ├── reporting.sh                 # 🆕 Results and logging
│   ├── logging.sh                   # ✅ Keep as-is (minor cleanup)
│   ├── assert.sh                    # ✅ Keep as-is (minor cleanup)
│   ├── fixtures.sh                  # ✅ Keep as-is
│   ├── kgsm.sh                      # 🆕 KGSM integration layer
│   └── runner.sh                    # ♻️  Slim orchestrator
├── templates/
│   └── test.template.sh             # ♻️  Update header
├── unit/
├── integration/
├── e2e/
└── config/
    └── test.conf
```

**Legend:**
- 🆕 New file (extract from existing)
- ♻️ Refactored file (change structure)
- ✅ Keep as-is (minimal changes)

### 4.2 Architectural Layers

```
┌─────────────────────────────────────────────────────────┐
│  Layer 1: Entry Point                                   │
│  run.sh → Validates environment, executes runner.sh     │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Layer 2: Orchestration                                 │
│  runner.sh → Parse args, call main(), coordinate phases │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Layer 3: Bootstrap & Loading                           │
│  bootstrap.sh → TEST_ROOT, KGSM_ROOT, load common.sh    │
│  loader.sh → Path constants, color constants, helpers   │
│  common.sh → Load all specialized modules               │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Layer 4: Framework Modules (Independent)               │
│  config.sh    → Test configuration management           │
│  sandbox.sh   → Sandbox creation/cleanup                │
│  discovery.sh → Test finding and filtering              │
│  execution.sh → Test running and output capture         │
│  reporting.sh → Results generation and summary          │
│  logging.sh   → Structured logging (keep existing)      │
│  assert.sh    → Assertion library (keep existing)       │
│  fixtures.sh  → Test data creation (keep existing)      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  Layer 5: KGSM Integration (Isolated)                   │
│  kgsm.sh → KGSM-specific helpers (create instance, etc) │
└─────────────────────────────────────────────────────────┘
```

### 4.3 Design Principles

1. **Downward Dependencies Only:** Higher layers depend on lower layers, never upward
2. **Single Responsibility:** Each module has exactly one job
3. **Independent Modules:** Layer 4 modules don't depend on each other
4. **Isolation:** KGSM-specific code only in `kgsm.sh`
5. **Consistent Patterns:** All modules use same structure (load guards, exports)

---

## 5. Module Responsibilities

### 5.1 Core Framework Modules

| Module           | Primary Responsibility        | Key Functions                                                 | Dependencies          |
| ---------------- | ----------------------------- | ------------------------------------------------------------- | --------------------- |
| **bootstrap.sh** | Initialize test environment   | Detect TEST_ROOT, KGSM_ROOT, handle --debug, source common.sh | None (entry point)    |
| **loader.sh**    | Provide constants and helpers | Export paths, color constants, helper functions               | None                  |
| **common.sh**    | Orchestrate module loading    | Source all framework modules in correct order                 | loader.sh             |
| **config.sh**    | Manage test configuration     | Load test.conf, initialize test environment                   | loader.sh             |
| **sandbox.sh**   | Manage sandbox lifecycle      | Create sandbox, create test config, cleanup                   | loader.sh, config.sh  |
| **discovery.sh** | Find and filter tests         | Discover tests, check skip conditions, apply patterns         | loader.sh, config.sh  |
| **execution.sh** | Execute individual tests      | Run test file, capture output, parse results                  | loader.sh, sandbox.sh |
| **reporting.sh** | Generate results and reports  | Create summary, manage logs, generate CSV                     | loader.sh             |
| **kgsm.sh**      | KGSM-specific integration     | Create/remove instances, run KGSM commands                    | loader.sh, KGSM core  |

### 5.2 Existing Modules (Minimal Changes)

| Module          | Responsibility                 | Changes Needed                                          |
| --------------- | ------------------------------ | ------------------------------------------------------- |
| **logging.sh**  | Structured logging with levels | Remove duplicate color constants, import from loader.sh |
| **assert.sh**   | Assertion library              | Remove duplicate colors and exit codes, use imports     |
| **fixtures.sh** | Test data creation helpers     | None (keep as-is)                                       |

### 5.3 Orchestration Files

| File                 | Responsibility              | Key Operations                                                    |
| -------------------- | --------------------------- | ----------------------------------------------------------------- |
| **run.sh**           | User-facing entry point     | Validate dependencies, check environment, exec runner.sh          |
| **runner.sh**        | Test framework orchestrator | Parse arguments, initialize environment, run test suites, cleanup |
| **test.template.sh** | Test file template          | Provide structure for new tests                                   |

---

## 6. Dependency Graph

### 6.1 Module Load Order

```
bootstrap.sh
    ├─→ Detects TEST_ROOT and KGSM_ROOT
    └─→ Sources common.sh
           ├─→ Sources loader.sh
           │      └─→ Exports: TEST_*, paths, colors, helpers
           ├─→ Sources config.sh
           │      └─→ Uses: loader.sh
           ├─→ Sources sandbox.sh
           │      └─→ Uses: loader.sh, config.sh
           ├─→ Sources discovery.sh
           │      └─→ Uses: loader.sh, config.sh
           ├─→ Sources execution.sh
           │      └─→ Uses: loader.sh, sandbox.sh
           ├─→ Sources reporting.sh
           │      └─→ Uses: loader.sh
           ├─→ Sources logging.sh
           │      └─→ Uses: loader.sh (for colors)
           ├─→ Sources assert.sh
           │      └─→ Uses: loader.sh (for colors), KGSM errors.sh (for codes)
           ├─→ Sources fixtures.sh
           │      └─→ Uses: loader.sh
           └─→ Sources kgsm.sh
                  └─→ Uses: loader.sh, KGSM core modules
```

### 6.2 Dependency Rules

1. **No Circular Dependencies:** If A depends on B, B cannot depend on A
2. **No Peer Dependencies:** Modules at Layer 4 don't depend on each other
3. **Upward Data Flow:** Lower layers provide services, upper layers consume
4. **Explicit Dependencies:** Each module lists what it needs at the top

### 6.3 Visual Dependency Map

```
                    ┌─────────────┐
                    │ bootstrap.sh│
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │  common.sh  │
                    └──────┬──────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
    ┌────▼────┐     ┌──────▼───────┐    ┌────▼────┐
    │loader.sh│     │   Layer 4    │    │KGSM core│
    └────┬────┘     │   Modules    │    └────┬────┘
         │          └──────┬───────┘         │
         │                 │                 │
         └────────┬────────┴────────┬────────┘
                  │                 │
         ┌────────▼────────┐ ┌──────▼──────┐
         │  Framework      │ │   KGSM      │
         │  Operations     │ │ Integration │
         └─────────────────┘ └─────────────┘
```

---

## 7. Execution Flow

### 7.1 Test Framework Startup

```
1. User runs: ./tests/run.sh unit

2. run.sh:
   ├─ Validates bash version, dependencies
   ├─ Checks for essential files
   └─ Executes: runner.sh unit

3. runner.sh:
   ├─ Sources: framework/bootstrap.sh
   │
   4. bootstrap.sh:
      ├─ Detects TEST_ROOT (tests/)
      ├─ Detects KGSM_ROOT (../)
      ├─ Handles --debug flag
      └─ Sources: framework/common.sh
         │
         5. common.sh:
            ├─ Sources: loader.sh      (constants)
            ├─ Sources: config.sh      (test config)
            ├─ Sources: sandbox.sh     (sandbox mgmt)
            ├─ Sources: discovery.sh   (test finding)
            ├─ Sources: execution.sh   (test running)
            ├─ Sources: reporting.sh   (results)
            ├─ Sources: logging.sh     (logging)
            ├─ Sources: assert.sh      (assertions)
            ├─ Sources: fixtures.sh    (test data)
            ├─ Sources: kgsm.sh        (KGSM integration)
            └─ Sources: KGSM core/bootstrap.sh
   │
   ├─ Parses arguments (unit, --pattern, etc.)
   ├─ Calls: initialize_test_environment()
   └─ Calls: main()

6. main() in runner.sh:
   ├─ Calls: load_test_config()        [config.sh]
   ├─ Calls: discover_tests("unit")    [discovery.sh]
   ├─ Calls: execute_test() for each   [execution.sh]
   │   └─ Calls: create_sandbox()      [sandbox.sh]
   └─ Calls: generate_summary()        [reporting.sh]
```

### 7.2 Individual Test Execution

```
1. execution.sh calls: execute_test(test_file, test_type)

2. create_sandbox():
   ├─ Creates /tmp/kgsm-test-sandbox-XXXX/unit_test_name_$$
   ├─ Copies entire KGSM → sandbox
   ├─ Calls: create_test_config(sandbox_path)
   │   └─ Creates sandbox/config.ini with test overrides
   └─ Returns: sandbox_path

3. Set environment for test:
   ├─ KGSM_ROOT = sandbox_path
   ├─ KGSM_TEST_MODE = true
   ├─ KGSM_TEST_LOG = /path/to/test.log
   └─ KGSM_TEST_SANDBOX = sandbox_path

4. Execute test file:
   ├─ Test sources: ../framework/bootstrap.sh
   ├─ Bootstrap loads all framework modules (in sandbox context)
   ├─ Test runs: setup_test() → test_*() → main()
   └─ Framework captures: output, exit code, assertions

5. Parse results:
   ├─ Count assertions (PASS/FAIL)
   ├─ Record to CSV
   └─ Update global counters

6. Cleanup:
   ├─ Restore KGSM_ROOT to original
   └─ cleanup_sandbox(sandbox_path)
```

### 7.3 Context Separation

**Host Context** (Framework Execution):
```
KGSM_ROOT=/home/user/kgsm               (Original KGSM)
TEST_ROOT=/home/user/kgsm/tests         (Framework location)
```

**Sandbox Context** (Test Execution):
```
KGSM_ROOT=/tmp/sandbox-123/             (Sandboxed KGSM copy)
KGSM_TEST_SANDBOX=/tmp/sandbox-123/     (Same as KGSM_ROOT)
TEST_ROOT=/home/user/kgsm/tests         (Unchanged - framework)
```

**Key Insight:** `TEST_ROOT` never changes (always points to framework), `KGSM_ROOT` switches to sandbox during test execution.

---

## 8. Migration Strategy

### 8.1 Phased Approach

| Phase       | Duration  | Objective                                                          | Validation                                   |
| ----------- | --------- | ------------------------------------------------------------------ | -------------------------------------------- |
| **Phase 1** | Week 1    | Create foundation (bootstrap.sh, loader.sh)                        | 3 canary tests pass                          |
| **Phase 2** | Weeks 2-3 | Extract modules (sandbox, config, discovery, execution, reporting) | Full test suite passes after each extraction |
| **Phase 3** | Week 4    | Cleanup & integration (refactor common, extract kgsm.sh)           | All tests pass                               |
| **Phase 4** | Week 4    | Deduplication (colors, exit codes, logging)                        | Code quality improvements verified           |
| **Phase 5** | Week 5    | Validation & documentation                                         | Full test suite + framework tests pass       |

### 8.2 Phase Details

#### Phase 1: Foundation (Week 1)
**Goal:** Establish bootstrap pattern

**Tasks:**
1. Create `tests/framework/bootstrap.sh`
   - Detect TEST_ROOT and KGSM_ROOT
   - Handle --debug flag
   - Source common.sh
   - Export TEST_BOOTSTRAP_LOADED=1

2. Create `tests/framework/loader.sh`
   - Define all path constants (TEST_FRAMEWORK_DIR, etc.)
   - Define all color constants (TEST_COLOR_*)
   - Create helper functions (__test_find_tests, etc.)
   - Export TEST_LOADER_LOADED=1

3. Update `tests/templates/test.template.sh`
   - Change header to: `source "$SCRIPT_DIR/../framework/bootstrap.sh"`
   - Remove redundant sourcing

**Validation:** Run 2-3 simple unit tests to verify bootstrap works

#### Phase 2: Module Extraction (Weeks 2-3)
**Goal:** Separate concerns into dedicated modules

**Tasks:**
1. Extract `tests/framework/sandbox.sh` from runner.sh lines 141-217
   - Functions: create_sandbox(), create_test_config(), cleanup_sandbox()
   - Add load guard and exports

2. Extract `tests/framework/config.sh` from runner.sh lines 113-137
   - Functions: load_test_config(), initialize_test_environment()
   - Add load guard and exports

3. Extract `tests/framework/discovery.sh` from runner.sh lines 226-278
   - Functions: discover_tests(), should_run_test()
   - Add load guard and exports

4. Extract `tests/framework/execution.sh` from runner.sh lines 280-416
   - Functions: execute_test(), run_test_suite()
   - Add load guard and exports

5. Extract `tests/framework/reporting.sh` from runner.sh lines 451-516
   - Functions: generate_summary(), clean_old_logs()
   - Add load guard and exports

**Validation:** After each extraction, run full test suite to ensure no regressions

#### Phase 3: Cleanup & Integration (Week 4)
**Goal:** Refactor remaining files, establish clean architecture

**Tasks:**
1. Refactor `tests/framework/common.sh`
   - Remove all function definitions
   - Keep only: load guards + source statements + KGSM bootstrap source
   - Should be <50 lines

2. Extract `tests/framework/kgsm.sh` from common.sh lines 192-273
   - Functions: create_test_instance(), remove_test_instance(), instance_exists(), run_kgsm()
   - Add load guard and exports

3. Refactor `tests/framework/runner.sh`
   - Remove extracted functions
   - Keep only: argument parsing, main(), cleanup_all()
   - Should be <200 lines

**Validation:** Full test suite passes with new architecture

#### Phase 4: Deduplication (Week 4)
**Goal:** Eliminate all code duplication

**Tasks:**
1. Remove color constants from:
   - tests/run.sh (lines 10-18)
   - tests/framework/logging.sh (lines 40-52, use imports instead)
   - tests/framework/assert.sh (lines 28-39, use imports instead)
   - tests/framework/common.sh (lines 51-60, use imports instead)

2. Remove exit code redefinitions from:
   - tests/framework/assert.sh (lines 19-22)
   - tests/framework/common.sh (lines 47-50)
   - Use KGSM core's errors.sh instead

3. Consolidate logging:
   - Remove log_message() from runner.sh
   - Remove duplicate log functions from common.sh
   - Use logging.sh API exclusively

**Validation:** No functionality changes, all tests still pass

#### Phase 5: Validation (Week 5)
**Goal:** Comprehensive testing and documentation

**Tasks:**
1. Create framework module tests:
   - tests/framework/test_bootstrap.sh
   - tests/framework/test_loader.sh
   - tests/framework/test_sandbox.sh
   - tests/framework/test_discovery.sh
   - tests/framework/test_execution.sh

2. Run full test suite 3x consecutively (ensure stability)

3. Update documentation:
   - docs/testing_framework.md
   - tests/README.md
   - Add architecture diagrams

**Validation:** All tests (including framework tests) pass 3 consecutive times

### 8.3 Rollback Strategy

**Git Strategy:**
- Create branch: `refactor/testing-framework`
- Tag after each phase: `refactor-phase-1`, `refactor-phase-2`, etc.
- If phase fails validation, rollback to previous tag

**Validation Gates:**
- Each phase must pass validation before proceeding
- "Pass" = full test suite runs successfully 3 times
- Document any skipped tests with reasons

---

## 9. Success Criteria

### 9.1 Quantitative Metrics

| Metric                     | Current  | Target | Measurement                               |
| -------------------------- | -------- | ------ | ----------------------------------------- |
| runner.sh LOC              | 665      | <200   | `wc -l tests/framework/runner.sh`         |
| common.sh responsibilities | 8+       | 1      | Manual review: should only source modules |
| Color constant definitions | 5        | 1      | `grep -r "readonly RED" tests/framework/` |
| Exit code definitions      | 3        | 1      | Use KGSM core only                        |
| Module count               | 5        | 11     | Count files in framework/                 |
| Average module LOC         | Variable | <250   | Exclude logging.sh (already good)         |

### 9.2 Qualitative Metrics

| Criterion           | Validation Method                                         |
| ------------------- | --------------------------------------------------------- |
| **Clarity**         | New developer can explain each module's purpose in <5 min |
| **Consistency**     | All modules follow same pattern (load guards, structure)  |
| **Testability**     | Each module can be unit tested independently              |
| **Maintainability** | Bugs can be isolated to specific module in <10 min        |
| **Extensibility**   | New test type can be added without changing core modules  |

### 9.3 Test Suite Health

**Requirement:** All existing tests must pass without modification during refactoring

| Test Type         | Count | Status Requirement     |
| ----------------- | ----- | ---------------------- |
| Unit Tests        | ~40   | 100% pass (0 failures) |
| Integration Tests | ~15   | 100% pass (0 failures) |
| E2E Tests         | ~10   | 100% pass (0 failures) |

**Note:** Tests will be updated in a separate phase AFTER framework refactoring completes

---

## 10. Next Steps

### 10.1 Technical Specification Documents

After approving this architectural specification, create individual technical specs for each new module:

1. **`bootstrap.sh` Technical Spec**
   - Exact implementation of TEST_ROOT detection
   - Debug flag handling mechanism
   - Error handling for missing files

2. **`loader.sh` Technical Spec**
   - Complete list of path constants
   - Color constant naming convention
   - Helper function signatures and implementations

3. **`sandbox.sh` Technical Spec**
   - Sandbox creation algorithm
   - Test config template structure
   - Cleanup safety checks

4. **`config.sh` Technical Spec**
   - Configuration file format
   - Environment variable exports
   - Default value handling

5. **`discovery.sh` Technical Spec**
   - Test file pattern matching
   - Skip condition evaluation
   - Filter application logic

6. **`execution.sh` Technical Spec**
   - Test process management
   - Output capture mechanism
   - Result parsing algorithm

7. **`reporting.sh` Technical Spec**
   - Summary format specification
   - CSV schema definition
   - Log management policy

8. **`kgsm.sh` Technical Spec**
   - KGSM command wrapper API
   - Instance lifecycle management
   - Error handling for KGSM operations

### 10.2 Implementation Sequence

```
Week 1:
├─ Day 1-2: Approve architectural spec
├─ Day 3:   Create bootstrap.sh + loader.sh technical specs
├─ Day 4:   Implement bootstrap.sh + loader.sh
└─ Day 5:   Validate with canary tests

Weeks 2-3:
├─ Create technical spec for one module
├─ Implement module
├─ Run full test suite
└─ Repeat for next module

Week 4:
├─ Refactor remaining files
├─ Deduplicate code
└─ Clean up and optimize

Week 5:
├─ Create framework tests
├─ Run validation suite
└─ Update documentation
```

### 10.3 Decision Points

**Before Phase 1:**
- [ ] Approve this architectural specification
- [ ] Decide on color constant naming: `TEST_COLOR_*` vs `TEST_*` vs other?
- [ ] Decide on function naming: `__test_*` for internal helpers?

**Before Phase 2:**
- [ ] Approve each module's technical specification before implementation
- [ ] Decide on error handling strategy: exit immediately or collect errors?

**Before Phase 5:**
- [ ] Decide scope of framework tests: full coverage or critical path only?
- [ ] Decide documentation format: update existing or create new?

---

## Appendix A: Reference Materials

### A.1 Current File Locations

```
tests/run.sh                        # Entry point
tests/framework/runner.sh           # Main orchestrator (665 lines)
tests/framework/common.sh           # Catch-all utilities (~500 lines)
tests/framework/logging.sh          # Logging module (327 lines)
tests/framework/assert.sh           # Assertions (806 lines)
tests/framework/fixtures.sh         # Test data (243 lines)
tests/templates/test.template.sh    # Test template
tests/config/test.conf              # Test configuration
```

### A.2 Key KGSM Core Files

```
core/bootstrap.sh                   # KGSM initialization pattern (58 lines)
core/loader.sh                      # Path constants and helpers (423 lines)
core/common.sh                      # Module orchestrator (100 lines)
core/errors.sh                      # Exit code definitions
```

### A.3 Lines to Extract

| Module       | Source File | Line Range | Functions                                           |
| ------------ | ----------- | ---------- | --------------------------------------------------- |
| sandbox.sh   | runner.sh   | 141-217    | create_sandbox, create_test_config, cleanup_sandbox |
| config.sh    | runner.sh   | 113-137    | load_test_config, initialize_test_environment       |
| discovery.sh | runner.sh   | 226-278    | discover_tests, should_run_test                     |
| execution.sh | runner.sh   | 280-416    | execute_test, run_test_suite                        |
| reporting.sh | runner.sh   | 451-516    | generate_summary, clean_old_logs                    |
| kgsm.sh      | common.sh   | 192-273    | create_test_instance, remove_test_instance, etc.    |

### A.4 Variables to Standardize

**Path Constants:**
```bash
TEST_ROOT                  # tests/ directory
TEST_FRAMEWORK_DIR         # tests/framework/
TEST_UNIT_DIR              # tests/unit/
TEST_INTEGRATION_DIR       # tests/integration/
TEST_E2E_DIR              # tests/e2e/
TEST_LOGS_DIR             # tests/logs/
TEST_CONFIG_FILE          # tests/config/test.conf
```

**Color Constants (Proposed):**
```bash
TEST_COLOR_RED
TEST_COLOR_GREEN
TEST_COLOR_YELLOW
TEST_COLOR_BLUE
TEST_COLOR_CYAN
TEST_COLOR_WHITE
TEST_COLOR_GRAY
TEST_COLOR_NC
TEST_COLOR_BOLD
```

**Test Context Variables:**
```bash
TEST_DEBUG                 # true/false
TEST_VERBOSE              # true/false
TEST_SANDBOX_ROOT         # /tmp/kgsm-test-sandbox-*/
TEST_LOG_DIR              # tests/logs/YYYY-MM-DD_HH-MM-SS/
KGSM_TEST_MODE           # true (when test is running)
KGSM_TEST_LOG            # Path to individual test log
KGSM_TEST_SANDBOX        # Path to current test's sandbox
```

---

## Appendix B: Glossary

| Term                   | Definition                                                     |
| ---------------------- | -------------------------------------------------------------- |
| **Bootstrap**          | Initial environment setup and detection (TEST_ROOT, KGSM_ROOT) |
| **Loader**             | Module that exports constants and helper functions             |
| **Orchestrator**       | Module that coordinates loading other modules (common.sh)      |
| **Sandbox**            | Isolated KGSM copy for test execution                          |
| **Test Context**       | Environment variables and state during test execution          |
| **Load Guard**         | Code that prevents module from loading twice                   |
| **Specialized Module** | Module with single, focused responsibility                     |
| **Integration Layer**  | Module that bridges framework with external system (KGSM)      |
| **Canary Test**        | Simple test used to validate framework changes                 |
| **Validation Gate**    | Checkpoint requiring success before proceeding                 |

---

**End of Specification**

This document defines the architectural blueprint for refactoring the KGSM testing framework. Individual technical specifications for each module will detail implementation specifics.

**Next Action:** Review and approve this architecture, then create technical specification for `bootstrap.sh` and `loader.sh`.
