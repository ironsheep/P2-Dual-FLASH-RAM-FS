#!/bin/bash
#
# run_test.sh - Compile, download, run, and monitor P2 test files
#
# Usage: run_test.sh [basename] [srcdir] [-t timeout] [-m] [-l]
#        Run without arguments to use defaults below.
#
# ============================================================
# CURRENT TEST CONFIGURATION (edit these for your test)
# ============================================================
DEFAULT_BASENAME="RT_ram_read_write_tests"
DEFAULT_SRCDIR="../tests"
DEFAULT_TIMEOUT="60"
# ============================================================
#
# Arguments (override defaults):
#   basename  - Source file name without .spin2 extension
#   srcdir    - Directory containing the source file
#   -t <sec>  - Timeout in seconds
#   -m        - (optional) Generate memory map file
#   -l        - (optional) Generate listing file
#
# Exit codes:
#   0 - Test completed successfully (END_SESSION found)
#   1 - Compilation failed
#   2 - Download/run failed (no log file, or pnut-term-ts failed to start)
#   3 - Timeout expired (END_SESSION not found in time)
#   4 - Usage error
#
# The script coordinates:
#   - pnut-term-ts running in foreground with GUI
#   - Background log monitor watching for END_SESSION
#   - Timeout watchdog
# All child processes are cleaned up on exit.
#

# Disable set -e since we're doing our own error handling
set +e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Global Variables ---
LOG_FILE=""
EXIT_CODE=3  # Default to timeout

# --- Cleanup Function ---
cleanup() {
    # Nothing to clean up - timeout command handles process termination
    :
}

# --- Detect timeout command ---
# macOS uses gtimeout (from coreutils), Linux uses timeout
if command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout"
elif command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout"
else
    echo -e "${RED}Error: 'timeout' or 'gtimeout' command not found${NC}"
    echo "  Install with: brew install coreutils"
    exit 4
fi

# Set trap to ensure cleanup on any exit
trap cleanup EXIT

# --- Functions ---

usage() {
    echo "Usage: $0 [basename] [srcdir] [-t timeout] [-m] [-l]"
    echo ""
    echo "Run without arguments to use defaults:"
    echo "  BASENAME: $DEFAULT_BASENAME"
    echo "  SRCDIR:   $DEFAULT_SRCDIR"
    echo "  TIMEOUT:  $DEFAULT_TIMEOUT seconds"
    echo ""
    echo "Arguments (override defaults):"
    echo "  basename  - Source file name without .spin2 extension"
    echo "  srcdir    - Directory containing the source file"
    echo "  -t <sec>  - Timeout in seconds"
    echo "  -m        - Generate memory map file"
    echo "  -l        - Generate listing file"
    echo ""
    echo "Exit codes:"
    echo "  0 - Test passed (END_SESSION found)"
    echo "  1 - Compilation failed"
    echo "  2 - Download/run failed"
    echo "  3 - Timeout (END_SESSION not found)"
    echo "  4 - Usage error"
    exit 4
}

# --- Parse Arguments (use defaults if not provided) ---

BASENAME=""
SRCDIR=""
TIMEOUT_SECS=""
MAP_FLAG=""
LIST_FLAG=""

# Parse positional args first (basename, srcdir)
while [[ $# -gt 0 && ! "$1" == -* ]]; do
    if [[ -z "$BASENAME" ]]; then
        BASENAME="$1"
    elif [[ -z "$SRCDIR" ]]; then
        SRCDIR="$1"
    fi
    shift
done

# Parse optional flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo -e "${RED}Error: -t requires a timeout value in seconds${NC}"
                usage
            fi
            TIMEOUT_SECS="$2"
            shift 2
            ;;
        -m) MAP_FLAG="-m"; shift ;;
        -l) LIST_FLAG="-l"; shift ;;
        -h|--help) usage ;;
        *) echo -e "${RED}Error: Unknown option: $1${NC}"; usage ;;
    esac
done

# Apply defaults for any missing values
BASENAME="${BASENAME:-$DEFAULT_BASENAME}"
SRCDIR="${SRCDIR:-$DEFAULT_SRCDIR}"
TIMEOUT_SECS="${TIMEOUT_SECS:-$DEFAULT_TIMEOUT}"

# Validate timeout is numeric
if ! [[ "$TIMEOUT_SECS" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: Timeout must be a positive integer${NC}"
    usage
fi

echo -e "${CYAN}Using: BASENAME=$BASENAME, SRCDIR=$SRCDIR, TIMEOUT=$TIMEOUT_SECS${NC}"

# --- Validate Arguments ---

if [[ ! -d "$SRCDIR" ]]; then
    echo -e "${RED}Error: Source directory does not exist: $SRCDIR${NC}"
    exit 4
fi

SOURCE_FILE="$SRCDIR/$BASENAME.spin2"
if [[ ! -f "$SOURCE_FILE" ]]; then
    echo -e "${RED}Error: Source file does not exist: $SOURCE_FILE${NC}"
    exit 4
fi

# --- Compilation ---

echo -e "${GREEN}=== Compiling $BASENAME.spin2 ===${NC}"

cd "$SRCDIR"

COMPILE_CMD="pnut-ts -d -I ../src $MAP_FLAG $LIST_FLAG $BASENAME.spin2"
echo "  Command: $COMPILE_CMD"

if ! $COMPILE_CMD; then
    echo -e "${RED}=== Compilation FAILED ===${NC}"
    exit 1
fi

BIN_FILE="$BASENAME.bin"
if [[ ! -f "$BIN_FILE" ]]; then
    echo -e "${RED}Error: Binary file not generated: $BIN_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}=== Compilation successful ===${NC}"

# --- Prepare for Download ---

# Ensure logs directory exists
mkdir -p ./logs

# Record time before starting (for finding new log files)
BEFORE_TIME=$(date +%s)

echo -e "${GREEN}=== Downloading to RAM and running ===${NC}"
echo "  Timeout: ${TIMEOUT_SECS} seconds"
echo "  Log dir: $(pwd)/logs/"
echo ""

# --- Run pnut-term-ts in TRUE FOREGROUND with timeout ---

echo -e "${YELLOW}>>> Running pnut-term-ts (timeout: ${TIMEOUT_SECS}s) <<<${NC}"
echo -e "${YELLOW}>>> Close the window or wait for test to complete <<<${NC}"
echo ""

# Run pnut-term-ts with timeout - TRUE FOREGROUND, GUI will appear
# The 'timeout' command will kill it if it exceeds the time limit
$TIMEOUT_CMD "$TIMEOUT_SECS" pnut-term-ts -u -r "$BIN_FILE"
PNUT_EXIT_CODE=$?

# timeout exit codes: 124 = timed out, otherwise pass through child's exit code
if [[ $PNUT_EXIT_CODE -eq 124 ]]; then
    echo ""
    echo -e "${YELLOW}>>> TIMEOUT ($TIMEOUT_SECS seconds) <<<${NC}"
fi

echo ""
echo -e "${GREEN}=== pnut-term-ts finished (exit code: $PNUT_EXIT_CODE) ===${NC}"

# Brief pause for log file to be written
sleep 0.5

# --- Check Results ---

echo ""
echo -e "${GREEN}=== Checking Results ===${NC}"

# Find the newest log file created after we started
NEWEST_LOG=$(ls -t ./logs/debug_*.log 2>/dev/null | head -1)
if [[ -n "$NEWEST_LOG" ]]; then
    LOG_MTIME=$(stat -f %m "$NEWEST_LOG" 2>/dev/null || stat -c %Y "$NEWEST_LOG" 2>/dev/null)
    if [[ "$LOG_MTIME" -ge "$BEFORE_TIME" ]]; then
        LOG_FILE="$NEWEST_LOG"
    fi
fi

# Report results
if [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]]; then
    echo -e "${RED}=== TEST FAILED (No log file created) ===${NC}"
    EXIT_CODE=2
else
    echo "  Log file: $LOG_FILE"
    echo ""
    echo "  Last 30 lines of log:"
    echo "  ----------------------"
    tail -30 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
    echo "  ----------------------"
    echo ""

    # Check if END_SESSION is in the log
    if grep -q "END_SESSION" "$LOG_FILE" 2>/dev/null; then
        echo -e "${GREEN}=== TEST PASSED (END_SESSION found) ===${NC}"
        EXIT_CODE=0
    else
        echo -e "${RED}=== TEST FAILED (END_SESSION not found) ===${NC}"
        EXIT_CODE=3
    fi
fi

exit $EXIT_CODE
