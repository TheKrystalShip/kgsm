#!/usr/bin/env bash

# KGSM Test Framework - Main Entry Point
#
# Author: The Krystal Ship Team
# Version: 3.0
#
# This is the main entry point for running KGSM tests.
# It provides a convenient interface to the test runner.

# =============================================================================
# SCRIPT SETUP
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$SCRIPT_DIR/framework"
RUNNER_SCRIPT="$FRAMEWORK_DIR/runner.sh"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;37m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

function print_banner() {
    echo -e "${CYAN}${BOLD}============================================================"
    echo "  KGSM Testing Framework"
    echo "============================================================"
    echo -e "${NC}"
}

self="$(basename "$0")"

function print_usage() {
    echo -e "
${BOLD}KGSM Test Framework${NC}

${BOLD}USAGE:${NC}
    ${self} [OPTIONS] [TEST_TYPES...]

${BOLD}OPTIONS:${NC}
    -h, --help          Show this help message
    -d, --debug         Enable debug mode (preserves test environments)
    -v, --verbose       Enable verbose output
    -q, --quiet         Suppress non-essential output
    -l, --list          List available tests without running them
    -c, --config FILE   Use specific test configuration file
    --clean-logs        Remove old test logs (keeps last 10)

${BOLD}FILTERING:${NC}
    --pattern REGEX     Only run tests matching pattern
    --exclude REGEX     Exclude tests matching pattern

${BOLD}TEST TYPES:${NC}
    unit                Run unit tests (fast, no dependencies)
    integration         Run integration tests (medium speed)
    e2e                 Run end-to-end tests (slow, requires network)
    all                 Run all test types (default)

${BOLD}EXAMPLES:${NC}
    ${self}                           # Run all tests
    ${self} unit                      # Run only unit tests
    ${self} --debug e2e               # Run e2e tests with debug
    ${self} --pattern \"instance\"     # Run tests matching \"instance\"
    ${self} --verbose --exclude \"long\"  # Verbose mode, exclude long tests

${BOLD}CONFIGURATION:${NC}
    Test behavior can be customized by editing:
    ${SCRIPT_DIR}/config/test.conf

    Individual tests can be skipped by setting:
    SKIP_<TEST_NAME>=true

${BOLD}REQUIREMENTS:${NC}
    - Bash 4.0+
    - Standard Unix utilities (grep, jq, wget, etc.)
    - SteamCMD (for Steam-based game tests)
    - Docker (for container-based game tests)

${BOLD}OUTPUT:${NC}
    - Test results are displayed with colored output
    - Detailed logs are saved to tests/logs/ with timestamps
    - CSV results file is generated for analysis
    - Failed tests show last 10 lines of logs in verbose mode
    - Use --clean-logs to manage old log directories

For more information, see: ${SCRIPT_DIR}/README.md
"
}

function check_dependencies() {
  local missing_deps=()

  # Check for runner script
  if [[ ! -f "$RUNNER_SCRIPT" ]]; then
    echo -e "${RED}ERROR: Test runner not found: $RUNNER_SCRIPT${NC}" >&2
    exit 1
  fi

  # Check for required commands
  local required_commands=("bash" "grep" "find" "mktemp" "date")

  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
      missing_deps+=("$cmd")
    fi
  done

  # Check optional but recommended commands
  local optional_commands=("jq" "steamcmd" "docker")
  local missing_optional=()

  for cmd in "${optional_commands[@]}"; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
      missing_optional+=("$cmd")
    fi
  done

  # Report missing dependencies
  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo -e "${RED}ERROR: Missing required dependencies:${NC}" >&2
    printf "${RED}  - %s${NC}\n" "${missing_deps[@]}" >&2
    echo -e "${RED}Please install these commands before running tests.${NC}" >&2
    exit 1
  fi

  if [[ ${#missing_optional[@]} -gt 0 ]]; then
    echo -e "${YELLOW}WARNING: Missing optional dependencies:${NC}" >&2
    printf "${YELLOW}  - %s${NC}\n" "${missing_optional[@]}" >&2
    echo -e "${YELLOW}Some tests may be skipped without these dependencies.${NC}" >&2
    echo ""
  fi
}

function validate_test_environment() {
  # Check that we're in the right directory structure
  if [[ ! -f "$SCRIPT_DIR/../kgsm.sh" ]]; then
    echo -e "${RED}ERROR: KGSM directory not found.${NC}" >&2
    echo -e "${RED}Tests must be run from within the KGSM project directory.${NC}" >&2
    exit 1
  fi

  # Check that essential test framework files exist
  local essential_files=(
    "$FRAMEWORK_DIR/bootstrap.sh"
    "$FRAMEWORK_DIR/sandbox.sh"
    "$FRAMEWORK_DIR/execution.sh"
    "$FRAMEWORK_DIR/execution.sequential.sh"
    "$FRAMEWORK_DIR/execution.parallel.sh"
    "$FRAMEWORK_DIR/discovery.sh"
    "$FRAMEWORK_DIR/reporting.sh"
    "$FRAMEWORK_DIR/runner.sh"
    "$FRAMEWORK_DIR/common.sh"
    "$FRAMEWORK_DIR/assert.sh"
  )

  for file in "${essential_files[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo -e "${RED}ERROR: Essential test file missing: $file${NC}" >&2
      exit 1
    fi
  done

  # Make sure runner is executable
  chmod +x "$RUNNER_SCRIPT"
}

export -f validate_test_environment

function _run_tests() {
  # Normal execution
  print_banner

  echo -e "${BLUE}Checking dependencies...${NC}"
  check_dependencies

  echo -e "${BLUE}Validating test environment...${NC}"
  validate_test_environment

  echo -e "${BLUE}Starting test execution...${NC}\n"

  # Execute the test runner with all arguments
  exec "$RUNNER_SCRIPT" "$@"
}

export -f _run_tests

# Parse command
command="${1:-}"

case "$command" in
  "")
    _run_tests "$@"
    ;;
  -h | --help | help)
    print_banner
    print_usage
    ;;
  -l | --list)
    # Delegate to runner.sh which uses discovery.sh list_tests()
    print_banner
    exec "$RUNNER_SCRIPT" --list "$@"
    ;;
  -c | --config)
    exec "$RUNNER_SCRIPT" "$@"
    ;;
  *)
    _run_tests "$@"
    ;;
esac

exit $?
