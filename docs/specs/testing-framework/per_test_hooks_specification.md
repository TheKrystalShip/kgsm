# Per-Test Setup/Teardown Hooks Specification

**Version:** 1.0
**Date:** March 8, 2026
**Status:** Planning

## 1. Problem Statement

KGSM's testing framework currently supports only **file-level** setup/teardown hooks (`setup_test()` / `cleanup_test()`), which run once before all test functions and once after all test functions in a file, respectively. This means all `test_*()` functions within a file share state — including filesystem artifacts, environment variables, and config modifications.

This architecture causes:

- **State pollution**: Test functions that create files, modify config, or export variables leave residue that affects subsequent test functions.
- **Fragile ordering**: Tests may pass or fail depending on execution order.
- **Scattered cleanup**: ~30 test files (53%) contain manual cleanup code at the end of individual `test_*()` functions, duplicating effort and risking incomplete cleanup on assertion failure.
- **Silent failures**: If a test function fails mid-execution (e.g., assertion failure before its cleanup code), subsequent tests run against corrupted state.

### Industry Standard

Every major testing framework distinguishes two levels of setup/teardown:

| Framework       | Per-Test (default)              | Per-Suite (optimization)               |
| --------------- | ------------------------------- | -------------------------------------- |
| Python unittest | `setUp()` / `tearDown()`        | `setUpClass()` / `tearDownClass()`     |
| pytest          | fixture `scope="function"`      | `scope="module"` / `scope="class"`     |
| JUnit 5 (Java)  | `@BeforeEach` / `@AfterEach`    | `@BeforeAll` / `@AfterAll`             |
| .NET xUnit      | Constructor / `Dispose()`       | `IClassFixture<T>`                     |
| .NET NUnit      | `[SetUp]` / `[TearDown]`        | `[OneTimeSetUp]` / `[OneTimeTearDown]` |
| Jest (JS)       | `beforeEach` / `afterEach`      | `beforeAll` / `afterAll`               |
| Go testing      | Each `Test*` runs independently | `TestMain()`                           |
| BATS (Bash)     | `setup()` / `teardown()`        | `setup_file()` / `teardown_file()`     |

The universal pattern: **per-test isolation is the default**; per-suite setup is the optimization for expensive shared resources.

KGSM currently only has the per-suite level, which is what every other framework treats as the optimization — not the default.

## 2. Proposed Solution

Add optional per-test `setup()` and `teardown()` hooks that run before and after **each** `test_*()` function, while preserving the existing `setup_test()` / `cleanup_test()` as file-level hooks.

### 2.1 Hook Naming Convention

Following BATS (the closest Bash analog) naming convention:

| Hook             | Scope    | When It Runs                               | Existing?          |
| ---------------- | -------- | ------------------------------------------ | ------------------ |
| `setup_test()`   | Per-file | Once, before the first `test_*()` function | ✅ Yes (keep as-is) |
| `setup()`        | Per-test | Before **each** `test_*()` function        | ❌ New              |
| `teardown()`     | Per-test | After **each** `test_*()` function         | ❌ New              |
| `cleanup_test()` | Per-file | Once, after the last `test_*()` function   | ✅ Yes (keep as-is) |

### 2.2 Execution Order

```
┌─────────────────────────────────────────────────────────┐
│ Test File Execution                                     │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. setup_test()          ← once per file               │
│                                                         │
│  2. ┌── setup()           ← before test_1               │
│     ├── test_1()                                        │
│     └── teardown()        ← after test_1                │
│                                                         │
│  3. ┌── setup()           ← before test_2               │
│     ├── test_2()                                        │
│     └── teardown()        ← after test_2                │
│                                                         │
│  4. ┌── setup()           ← before test_3               │
│     ├── test_3()                                        │
│     └── teardown()        ← after test_3                │
│                                                         │
│  5. print_assert_summary()                              │
│  6. cleanup_test()        ← once per file               │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### 2.3 Behavioral Rules

1. **Both hooks are optional.** If `setup()` or `teardown()` are not defined, they are silently skipped.
2. **`teardown()` always runs** if defined, even if the `test_*()` function fails. This guarantees cleanup.
3. **`teardown()` failures do not affect test results.** The test result is determined solely by assertions within `test_*()` (and `setup()` if it runs assertions).
4. **Assertion counters**: Per-function assertion tracking snapshots must be taken **after** `setup()` completes, so that setup assertions are not counted toward the test function's metrics. See [Section 3.2](#32-assertion-counter-placement) for details.
5. **All hooks share the same sandbox.** Per-test hooks do NOT create new sandboxes — they run within the file-level sandbox. This keeps overhead minimal.
6. **Backward compatible.** Existing tests that don't define `setup()` / `teardown()` continue to work identically.

## 3. Implementation Details

### 3.1 Target File

All changes are in `tests/framework/execution.common.sh`. Four code paths need modification:

| Path                        | Function                  | Lines   | Loop?         | Has Counter Tracking? |
| --------------------------- | ------------------------- | ------- | ------------- | --------------------- |
| Subprocess, multi-function  | `__capture_test_output()` | 209–237 | ✅ `for` loop  | ✅ Yes                 |
| Subprocess, single-function | `__capture_test_output()` | 179–204 | ❌ Conditional | ✅ Yes                 |
| Inline, multi-function      | `__execute_test_inline()` | 316–323 | ✅ `for` loop  | ❌ No                  |
| Inline, single-function     | `__execute_test_inline()` | 306–314 | ❌ Conditional | ❌ No                  |

### 3.2 Assertion Counter Placement

The current per-function tracking uses a snapshot/delta pattern:

```bash
# CURRENT (simplified)
for _fn in "${_test_functions[@]}"; do
  local _before_passed=${ASSERT_PASSED:-0}   # snapshot
  "$_fn"                                      # execute
  local _fn_passed=$(( ASSERT_PASSED - _before_passed ))  # delta
done
```

With per-test hooks, the snapshot must be taken **after** `setup()` so that any assertions in `setup()` are excluded from the test function's count:

```bash
# PROPOSED (simplified)
for _fn in "${_test_functions[@]}"; do
  # Run per-test setup (assertions here are NOT counted toward _fn)
  if declare -f setup >/dev/null 2>&1; then
    setup
  fi

  # Snapshot AFTER setup
  local _before_passed=${ASSERT_PASSED:-0}
  local _before_failed=${ASSERT_FAILED:-0}
  local _before_count=${ASSERT_COUNT:-0}

  "$_fn"  # execute test function

  # Calculate per-function deltas
  local _fn_passed=$(( ASSERT_PASSED - _before_passed ))
  local _fn_failed=$(( ASSERT_FAILED - _before_failed ))
  local _fn_total=$(( ASSERT_COUNT - _before_count ))

  # ... status determination and KGSM_FUNC_RESULT logging ...

  # Run per-test teardown (failures here do NOT affect test result)
  if declare -f teardown >/dev/null 2>&1; then
    teardown || true
  fi
done
```

### 3.3 Subprocess Multi-Function Path (Primary)

**Location:** `__capture_test_output()`, lines 209–237

**Current code:**
```bash
else
  local -a _test_functions
  mapfile -t _test_functions < <(grep -oP '^function \Ktest_\w+' "$test_file")
  for _fn in "${_test_functions[@]}"; do
    if declare -f "$_fn" >/dev/null 2>&1; then
      local _before_passed=${ASSERT_PASSED:-0}
      local _before_failed=${ASSERT_FAILED:-0}
      local _before_count=${ASSERT_COUNT:-0}
      local _before_skip_len=${#ASSERT_SKIPPED_FUNCTION_NAMES[@]}
      local _before_todo_len=${#ASSERT_TODO_FUNCTION_NAMES[@]}

      "$_fn"

      local _fn_passed=$(( ${ASSERT_PASSED:-0} - _before_passed ))
      local _fn_failed=$(( ${ASSERT_FAILED:-0} - _before_failed ))
      local _fn_total=$(( ${ASSERT_COUNT:-0} - _before_count ))
      local _fn_status="pass"

      if [[ ${#ASSERT_SKIPPED_FUNCTION_NAMES[@]} -gt $_before_skip_len ]]; then
        _fn_status="skip"
      elif [[ ${#ASSERT_TODO_FUNCTION_NAMES[@]} -gt $_before_todo_len ]]; then
        _fn_status="todo"
      elif [[ $_fn_failed -gt 0 ]]; then
        _fn_status="fail"
      fi

      if [[ -n "${KGSM_TEST_LOG:-}" ]]; then
        echo "KGSM_FUNC_RESULT: ${_fn}|${_fn_passed}|${_fn_failed}|${_fn_total}|${_fn_status}" >> "$KGSM_TEST_LOG"
      fi
    fi
  done
fi
```

**Proposed code:**
```bash
else
  local -a _test_functions
  mapfile -t _test_functions < <(grep -oP '^function \Ktest_\w+' "$test_file")
  for _fn in "${_test_functions[@]}"; do
    if declare -f "$_fn" >/dev/null 2>&1; then
      # Per-test setup (runs before each test function)
      if declare -f setup >/dev/null 2>&1; then
        setup
      fi

      # Snapshot counters AFTER setup() so setup assertions
      # are not counted toward the test function's metrics
      local _before_passed=${ASSERT_PASSED:-0}
      local _before_failed=${ASSERT_FAILED:-0}
      local _before_count=${ASSERT_COUNT:-0}
      local _before_skip_len=${#ASSERT_SKIPPED_FUNCTION_NAMES[@]}
      local _before_todo_len=${#ASSERT_TODO_FUNCTION_NAMES[@]}

      "$_fn"

      local _fn_passed=$(( ${ASSERT_PASSED:-0} - _before_passed ))
      local _fn_failed=$(( ${ASSERT_FAILED:-0} - _before_failed ))
      local _fn_total=$(( ${ASSERT_COUNT:-0} - _before_count ))
      local _fn_status="pass"

      if [[ ${#ASSERT_SKIPPED_FUNCTION_NAMES[@]} -gt $_before_skip_len ]]; then
        _fn_status="skip"
      elif [[ ${#ASSERT_TODO_FUNCTION_NAMES[@]} -gt $_before_todo_len ]]; then
        _fn_status="todo"
      elif [[ $_fn_failed -gt 0 ]]; then
        _fn_status="fail"
      fi

      if [[ -n "${KGSM_TEST_LOG:-}" ]]; then
        echo "KGSM_FUNC_RESULT: ${_fn}|${_fn_passed}|${_fn_failed}|${_fn_total}|${_fn_status}" >> "$KGSM_TEST_LOG"
      fi

      # Per-test teardown (runs after each test function, failures ignored)
      if declare -f teardown >/dev/null 2>&1; then
        teardown || true
      fi
    fi
  done
fi
```

### 3.4 Subprocess Single-Function Path

**Location:** `__capture_test_output()`, lines 179–204

Same pattern: insert `setup()` call before the counter snapshot, insert `teardown()` call after the KGSM_FUNC_RESULT log line.

### 3.5 Inline Multi-Function Path

**Location:** `__execute_test_inline()`, lines 316–323

Same pattern but without counter tracking (inline mode does not track per-function assertions):

```bash
for _fn in "${_test_functions[@]}"; do
  if declare -f "$_fn" >/dev/null 2>&1; then
    if declare -f setup >/dev/null 2>&1; then
      setup
    fi
    "$_fn"
    if declare -f teardown >/dev/null 2>&1; then
      teardown || true
    fi
  fi
done
```

### 3.6 Inline Single-Function Path

**Location:** `__execute_test_inline()`, lines 306–314

Same pattern around the single `"$KGSM_TEST_FUNCTION_FILTER"` call.

## 4. Documentation Updates

### 4.1 Files to Update

| File                                                    | What to Update                                                                         |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `tests/templates/test.template.sh`                      | Add `setup()` / `teardown()` examples and documentation                                |
| `docs/specs/testing-framework/testing_specification.md` | Update execution order (§Framework Execution Order), add per-test vs per-file guidance |
| `docs/testing_framework.md`                             | Add per-test hooks section, update "Writing Tests" example                             |
| `tests/README.md`                                       | Add per-test hook examples, update test file structure                                 |

### 4.2 Template Update

The test template should add documented (commented-out) examples:

```bash
# Optional: setup() is called by the framework BEFORE EACH test_*() function.
# Use for per-test resource creation, config reset, etc.
# function setup() {
#   log_test_step "Per-test setup"
#   # Create test-specific resources here
# }

# Optional: teardown() is called by the framework AFTER EACH test_*() function.
# Runs even if the test fails. Failures here do not affect the test result.
# function teardown() {
#   log_test_step "Per-test cleanup"
#   # Clean up test-specific resources here
# }
```

### 4.3 When-to-Use Guidance

Add a section to the testing specification:

| Use Case                                             | Hook                     | Why                                |
| ---------------------------------------------------- | ------------------------ | ---------------------------------- |
| Validate environment, source modules, verify sandbox | `setup_test()`           | Only needs to happen once per file |
| Create test-specific files/directories               | `setup()`                | Each test needs a clean slate      |
| Reset config values between tests                    | `setup()` / `teardown()` | Prevents state pollution           |
| Create/destroy instances                             | `setup()` / `teardown()` | Per-test isolation                 |
| Final resource cleanup                               | `cleanup_test()`         | Rarely needed (sandbox handles it) |

## 5. Testing the Implementation

### 5.1 Framework-Level Tests

Create `tests/unit/test_per_test_hooks.sh` to verify:

1. **`setup()` called before each test**: Define a `setup()` that creates a marker file with a counter; each test verifies the counter incremented.
2. **`teardown()` called after each test**: Define a `teardown()` that removes the marker; each test verifies it was cleaned from the previous run.
3. **`teardown()` runs on test failure**: A test with a failing assertion should still trigger `teardown()`.
4. **`teardown()` failures are ignored**: A `teardown()` that returns non-zero should not affect the test result.
5. **Backward compatibility**: A test file with no `setup()` / `teardown()` runs identically to before.
6. **Counter isolation**: Assertions in `setup()` are not counted toward the test function's per-function metrics.
7. **Coexistence**: `setup_test()` + `setup()` + `teardown()` + `cleanup_test()` all work together in the correct order.

### 5.2 Regression Testing

Run the full test suite before and after changes:

```bash
./tests/run.sh
```

All 57 existing test files must produce identical results since none define `setup()` or `teardown()`.

## 6. Migration Path for Existing Tests

### 6.1 Priority Tiers

**Tier 1 — High benefit (~15 files):** Tests with extensive internal cleanup code (e.g., `test_files_management_logic.sh` with 23 cleanup operations). Extract cleanup into `teardown()`.

**Tier 2 — Medium benefit (~10 files):** Tests that modify shared state (config, environment variables) and manually restore. Move restoration into `teardown()` for guaranteed execution.

**Tier 3 — Low/no benefit (~32 files):** Validation-only tests with no mutable state. No changes needed.

### 6.2 Migration is Optional

Existing tests continue working unchanged. Migration to per-test hooks is an improvement that can happen incrementally, file by file, as tests are maintained.

## 7. Risks and Mitigations

| Risk                                              | Severity | Mitigation                                                     |
| ------------------------------------------------- | -------- | -------------------------------------------------------------- |
| `setup()` name collision with existing functions  | Low      | Grep confirms no existing test defines `setup()` as a function |
| `teardown()` name collision                       | Low      | Grep confirms no existing test defines `teardown()`            |
| Performance overhead from repeated setup/teardown | Low      | Hooks only run if defined; no sandbox recreation               |
| `setup()` assertions inflating test counts        | Medium   | Counter snapshot placed AFTER `setup()` completes              |
| `teardown()` masking real failures                | Medium   | `teardown()` failures explicitly suppressed (`                 |  | true`) |
| Parallel execution safety                         | None     | Per-test hooks run within existing subprocess/sandbox model    |

## 8. Implementation Checklist

- [ ] Modify `__capture_test_output()` multi-function loop (lines 209–237)
- [ ] Modify `__capture_test_output()` single-function filter (lines 179–204)
- [ ] Modify `__execute_test_inline()` multi-function loop (lines 316–323)
- [ ] Modify `__execute_test_inline()` single-function filter (lines 306–314)
- [ ] Create `tests/unit/test_per_test_hooks.sh` with framework-level tests
- [ ] Update `tests/templates/test.template.sh` with hook documentation
- [ ] Update `docs/specs/testing-framework/testing_specification.md`
- [ ] Update `docs/testing_framework.md`
- [ ] Update `tests/README.md`
- [ ] Run full test suite regression
