# KGSM Test Templates

## Universal Test Template

**File:** `test.template.sh`

This is the **single universal template** for all KGSM tests (unit, integration, and E2E).

### Usage

```bash
# 1. Copy the template
cp tests/templates/test.template.sh tests/<type>/test_<name>.sh

# 2. Edit the file:
#    - Replace <PLACEHOLDERS> with actual values
#    - Implement test functions
#    - Update main() to call your functions

# 3. Run it
./tests/run.sh --pattern <name>
```

### Template Structure

The template includes:
- **Setup section** - Sourcing framework, declaring constants
- **Test functions** - Example patterns for all test types
- **Main function** - Single entry point that orchestrates tests

### Example Test Patterns Included

The template provides commented examples for:
- **Logic layer tests** - Testing pure `__logic_*` functions
- **Command layer tests** - Testing CLI interface
- **Error handling tests** - Testing invalid inputs and edge cases
- **Integration workflow tests** - Testing multi-module interactions
- **Complete E2E workflow tests** - Testing full user scenarios

Simply uncomment and modify the patterns that match your test needs.

### Key Principles

1. **Minimal global code** - Only sourcing and constants at file level
2. **All logic in functions** - Every test operation inside a function
3. **log_step first** - Every test function MUST start with `log_step`
4. **main() entry point** - Single orchestration function
5. **Direct execution** - File ends with `main "$@"`

## Documentation

See `docs/specs/testing-framework/testing_specification.md` for complete testing guide.
