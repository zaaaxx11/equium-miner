#!/usr/bin/env bash
# ============================================================================
#  Equium Mining Status Monitor
#  Run this in a separate terminal while mine.sh is running.
#
#  USAGE:
#    ./monitor.sh              # default: refresh every 2 seconds
#    LOG_INTERVAL=5 ./monitor.sh   # refresh every 5 seconds
# ============================================================================

set -uo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
CYAN="\033[36m"
GREEN="\033[32m"
DIM="\033[2m"
BOLD="\033[1m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

LOG_INTERVAL="${LOG_INTERVAL:-2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINER_LOG="${SCRIPT_DIR}/.miner-output.log"

# Check if miner is running
if ! pgrep -f "equium-miner" >/dev/null 2>&1; then
    echo -e "${RED}[ERROR]${RESET} Miner is not running! Start mining first with ./mine.sh"
    exit 1
fi

echo -e "${CYAN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}║${RESET}  ${BOLD}Equium Mining Status Monitor${RESET}              ${CYAN}║${RESET}"
echo -e "${CYAN}║${RESET}  ${DIM}Refreshing every ${LOG_INTERVAL}s — Press Ctrl+C to stop${RESET}  ${CYAN}║${RESET}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${RESET}"
echo ""

# If no log file exists yet, create one by capturing miner output
if [ ! -f "$MINER_LOG" ] || [ ! -s "$MINER_LOG" ]; then
    echo -e "${YELLOW}[WARN]${RESET}  No miner log found. Capturing output from running miner..."
    # Capture from /proc if available
    MINER_PID=$(pgrep -f "equium-miner" | head -1)
    if [ -n "$MINER_PID" ] && [ -d "/proc/$MINER_PID" ]; then
        # Try to read miner's stdout
        echo -e "${DIM}Monitoring miner PID: ${MINER_PID}${RESET}"
    fi
fi

STARTED_TS=$(date +%s)

while true; do
    # Check if miner is still running
    if ! pgrep -f "equium-miner" >/dev/null 2>&1; then
        echo ""
        echo -e "${RED}[INFO]${RESET}  Miner has stopped."
        exit 0
    fi

    # Calculate uptime
    NOW_TS=$(date +%s)
    ELAPSED=$((NOW_TS - STARTED_TS))
    HOURS=$((ELAPSED / 3600))
    MINS=$(( (ELAPSED % 3600) / 60 ))
    SECS=$((ELAPSED % 60))
    UPTIME=$(printf "%02d:%02d:%02d" $HOURS $MINS $SECS)

    # Read stats from log file if available
    if [ -f "$MINER_LOG" ] && [ -s "$MINER_LOG" ]; then
        MINED=$(grep -c "MINED" "$MINER_LOG" 2>/dev/null | head -1 | tr -dc '0-9')
        MINED=${MINED:-0}

        TRIES=$(grep -c "try #" "$MINER_LOG" 2>/dev/null | head -1 | tr -dc '0-9')
        TRIES=${TRIES:-0}

        ROUND=$(grep -o "round #[0-9]*" "$MINER_LOG" 2>/dev/null | tail -1)
        ROUND=${ROUND:-"round #?"}

        LATEST_HS=$(grep -oE '[0-9]+\.[0-9]+ H/s' "$MINER_LOG" 2>/dev/null | tail -1)
        if [ -n "$LATEST_HS" ]; then
            HASHRATE="$LATEST_HS"
        elif [ "$TRIES" -gt 0 ] && [ "$ELAPSED" -gt 0 ]; then
            HR=$(python3 -c "print(f'{int(${TRIES})/int(${ELAPSED}):.2f}')" 2>/dev/null || echo "0.00")
            HASHRATE="${HR} H/s"
        else
            HASHRATE="warming up"
        fi
    else
        MINED=0
        TRIES=0
        ROUND="round #?"
        HASHRATE="warming up"
    fi

    # CPU usage
    CPU_USAGE=$(top -bn1 2>/dev/null | grep -E 'Cpu|%cpu' | head -1 | awk '{printf "%.1f%%", $2+$4}' 2>/dev/null || echo "?%")

    # EQM earned
    EQM_EARNED=$((MINED * 25))

    # Print status bar
    echo -e "  ${CYAN}[STATUS]${RESET} ${DIM}uptime:${RESET}${UPTIME} ${DIM}|${RESET} ${BOLD}hashrate:${RESET}${HASHRATE} ${DIM}|${RESET} ${DIM}cpu:${RESET}${CPU_USAGE} ${DIM}|${RESET} ${DIM}${ROUND}${RESET} ${DIM}|${RESET} ${DIM}tries:${RESET}${TRIES} ${DIM}|${RESET} ${GREEN}mined:${RESET}${MINED} (${EQM_EARNED} EQM)"

    sleep "$LOG_INTERVAL"
done
