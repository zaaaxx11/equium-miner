#!/usr/bin/env bash
# ============================================================================
#  Equium ($EQM) Mining Script
#  CPU-mineable Solana token — Bitcoin-style economics, 21M cap, fair launch
#
#  Source: https://github.com/HannaPrints/equium
# ============================================================================
#
#  USAGE:
#    PRIVATE_KEY="<your_solana_private_key>" ./mine.sh
#
#  ENVIRONMENT VARIABLES:
#    PRIVATE_KEY     (required) Solana private key — accepts:
#                      - Base58 string (from Phantom/Solflare export)
#                      - Path to existing keypair JSON file
#    RPC_URL         Solana RPC endpoint (default: auto-select best public RPC)
#    THREADS         Number of CPU threads (default: all cores)
#    MAX_BLOCKS      Stop after N blocks (0 = run forever, default: 0)
#    CU_LIMIT        Compute-unit limit per tx (default: 1400000)
#    MAX_NONCES      Max nonce attempts per round per thread (default: 16384)
#    REBUILD         Set to 1 to force rebuild even if binary exists
#
#  EXAMPLES:
#    # Basic mining with all defaults
#    PRIVATE_KEY="5J3mBbAH..." ./mine.sh
#
#    # Custom RPC + 4 threads + higher nonce budget
#    PRIVATE_KEY="5J3mBbAH..." RPC_URL="https://rpc.ankr.com/solana" THREADS=4 MAX_NONCES=32768 ./mine.sh
#
#    # Using existing keypair file
#    PRIVATE_KEY="$HOME/.config/solana/id.json" ./mine.sh
#
#    # Force rebuild after upstream update
#    PRIVATE_KEY="5J3mBbAH..." REBUILD=1 ./mine.sh
#
#  NOTE: Equium uses Equihash (96,5) — a memory-bound PoW algorithm designed
#        to be CPU-friendly. GPU mining is NOT supported because Equihash
#        deliberately levels the playing field between CPUs and GPUs.
#        More threads = more parallelism on CPU.
# ============================================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Banner ──────────────────────────────────────────────────────────────────
echo -e "${MAGENTA}"
cat << 'BANNER'

 ███████╗ ██████╗ ██╗ ██╗██╗██╗ ██╗███╗   ███╗
 ██╔════╝██╔═══██╗██║ ██║██║██║ ██║████╗ ████║
 █████╗  ██║   ██║██║ ██║██║██║ ██║██╔████╔██║
 ██╔══╝  ██║▄▄ ██║██║ ██║██║██║ ██║██║╚██╔╝██║
 ███████╗╚██████╔╝╚██████╔╝██║╚██████╔╝██║ ╚═╝ ██║
 ╚══════╝ ╚══▀▀═╝  ╚═════╝ ╚═╝ ╚═════╝ ╚═╝     ╚═╝
                    MINER SCRIPT

BANNER
echo -e "${RESET}"

# ── Defaults ────────────────────────────────────────────────────────────────

# Public Solana RPC endpoints (free, tested in order for auto-select)
PUBLIC_RPCS=(
    "https://api.mainnet-beta.solana.com"
    "https://rpc.ankr.com/solana"
    "https://solana.drpc.org"
)

THREADS="${THREADS:-0}"
MAX_BLOCKS="${MAX_BLOCKS:-0}"
CU_LIMIT="${CU_LIMIT:-1400000}"
MAX_NONCES="${MAX_NONCES:-16384}"
REBUILD="${REBUILD:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EQUIUM_DIR="${SCRIPT_DIR}/equium"
KEYPAIR_FILE="${SCRIPT_DIR}/.miner-keypair.json"

# ── Helpers ─────────────────────────────────────────────────────────────────
log()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()  { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
ok()   { echo -e "${GREEN}[OK]${RESET}    $*"; }

# ── Cleanup on exit ─────────────────────────────────────────────────────────
cleanup() {
    if [ -f "$KEYPAIR_FILE" ]; then
        rm -f "$KEYPAIR_FILE"
        log "Keypair file cleaned up"
    fi
}
trap cleanup EXIT INT TERM

# ── Check dependencies FIRST ───────────────────────────────────────────────
check_deps() {
    local missing=()

    if ! command -v python3 &>/dev/null; then
        missing+=("python3")
    fi
    if ! command -v cargo &>/dev/null; then
        missing+=("rust/cargo")
    fi
    if ! command -v git &>/dev/null; then
        missing+=("git")
    fi
    if ! command -v curl &>/dev/null; then
        missing+=("curl")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        err "Missing dependencies: ${missing[*]}"
        echo ""
        echo -e "  ${BOLD}Install them:${RESET}"

        for dep in "${missing[@]}"; do
            case "$dep" in
                "rust/cargo")
                    echo -e "    ${DIM}curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh${RESET}"
                    ;;
                "git")
                    echo -e "    ${DIM}sudo apt install git  # or: brew install git${RESET}"
                    ;;
                "python3")
                    echo -e "    ${DIM}sudo apt install python3  # or: brew install python3${RESET}"
                    ;;
                "curl")
                    echo -e "    ${DIM}sudo apt install curl  # or: brew install curl${RESET}"
                    ;;
            esac
        done
        echo ""
        exit 1
    fi

    ok "All dependencies found (python3, cargo, git, curl)"
}

check_deps

# ── Validate PRIVATE_KEY ────────────────────────────────────────────────────
if [ -z "${PRIVATE_KEY:-}" ]; then
    err "PRIVATE_KEY is required."
    echo ""
    echo -e "  ${BOLD}Usage:${RESET}"
    echo -e "    ${DIM}PRIVATE_KEY=\"your_base58_private_key\" ./mine.sh${RESET}"
    echo -e "    ${DIM}PRIVATE_KEY=\"/path/to/keypair.json\" ./mine.sh${RESET}"
    echo ""
    echo -e "  ${BOLD}Available public RPCs:${RESET}"
    for rpc in "${PUBLIC_RPCS[@]}"; do
        echo -e "    ${DIM}${rpc}${RESET}"
    done
    echo ""
    exit 1
fi

# ── Convert private key to keypair JSON ─────────────────────────────────────
convert_private_key() {
    local key="$1"
    local output="$2"

    # Case 1: Path to existing keypair file
    if [ -f "$key" ]; then
        python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    assert isinstance(data, list) and len(data) == 64, 'Invalid keypair format'
    with open(sys.argv[2], 'w') as f:
        json.dump(data, f)
    print('Using existing keypair file: ' + sys.argv[1])
except Exception as e:
    print(f'ERROR: Invalid keypair file: {e}', file=sys.stderr)
    sys.exit(1)
" "$key" "$output" && return 0
    fi

    # Case 2: JSON byte array string like [1,2,3,...,64]
    if echo "$key" | grep -qE '^\['; then
        python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    assert isinstance(data, list) and len(data) == 64
    with open(sys.argv[2], 'w') as f:
        json.dump(data, f)
    print('Converted JSON byte array to keypair file')
except Exception as e:
    print(f'ERROR: Invalid JSON byte array: {e}', file=sys.stderr)
    sys.exit(1)
" "$key" "$output" && return 0
    fi

    # Case 3: Base58 private key string (from Phantom/Solflare wallet export)
    python3 -c "
import json, sys, os

ALPHABET = b'123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'

def b58decode(s):
    n = 0
    for c in s.encode():
        if c not in ALPHABET:
            raise ValueError(f'Invalid base58 character: {chr(c)}')
        n = n * 58 + ALPHABET.index(c)
    result = []
    while n > 0:
        result.append(n & 0xff)
        n >>= 8
    result.reverse()
    pad = 0
    for c in s.encode():
        if c == ALPHABET[0]:
            pad += 1
        else:
            break
    return b'\x00' * pad + bytes(result)

try:
    key_str = sys.argv[1].strip()
    key_bytes = b58decode(key_str)

    if len(key_bytes) == 64:
        keypair = list(key_bytes)
    elif len(key_bytes) == 32:
        try:
            import nacl.signing
            signing_key = nacl.signing.SigningKey(key_bytes)
            verify_key = signing_key.verify_key
            keypair = list(key_bytes) + list(bytes(verify_key))
        except ImportError:
            print('ERROR: 32-byte private key needs pynacl. Install: pip3 install pynacl', file=sys.stderr)
            print('Or export the full 64-byte keypair from your wallet.', file=sys.stderr)
            sys.exit(1)
    else:
        print(f'ERROR: Decoded key is {len(key_bytes)} bytes. Expected 64 or 32.', file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[2], 'w') as f:
        json.dump(keypair, f)

    os.chmod(sys.argv[2], 0o600)
    print(f'Converted base58 private key ({len(key_bytes)} bytes)')

except Exception as e:
    print(f'ERROR: Failed to convert private key: {e}', file=sys.stderr)
    sys.exit(1)
" "$PRIVATE_KEY" "$output"
}

log "Converting private key..."
convert_private_key "$PRIVATE_KEY" "$KEYPAIR_FILE"
chmod 600 "$KEYPAIR_FILE"
ok "Keypair file ready (permissions: 600)"

# ── Extract public key for display ──────────────────────────────────────────
PUBKEY=$(python3 -c "
import json, sys

ALPHABET = b'123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'

def b58encode(data):
    n = int.from_bytes(data, 'big')
    result = []
    while n > 0:
        n, r = divmod(n, 58)
        result.append(ALPHABET[r:r+1])
    result.reverse()
    pad = 0
    for b in data:
        if b == 0: pad += 1
        else: break
    return (b'1' * pad + b''.join(result)).decode()

with open(sys.argv[1]) as f:
    kp = json.load(f)
print(b58encode(bytes(kp[32:])))
" "$KEYPAIR_FILE")

# ── Auto-select best RPC ───────────────────────────────────────────────────
select_rpc() {
    if [ -n "${RPC_URL:-}" ]; then
        echo "$RPC_URL"
        return
    fi

    log "Testing public RPCs for best latency..."
    local best_rpc=""
    local best_time=999999

    for rpc in "${PUBLIC_RPCS[@]}"; do
        local start_ms
        start_ms=$(date +%s%N)
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 5 \
            -X POST "$rpc" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' 2>/dev/null) || http_code="000"
        local end_ms
        end_ms=$(date +%s%N)
        local elapsed_ms=$(( (end_ms - start_ms) / 1000000 ))

        if [ "$http_code" = "200" ]; then
            echo -e "    ${DIM}${rpc} — ${elapsed_ms}ms${RESET}" >&2
            if [ "$elapsed_ms" -lt "$best_time" ]; then
                best_time=$elapsed_ms
                best_rpc=$rpc
            fi
        else
            echo -e "    ${DIM}${rpc} — unreachable (${http_code})${RESET}" >&2
        fi
    done

    if [ -z "$best_rpc" ]; then
        warn "No public RPC reachable, falling back to default"
        echo "https://api.mainnet-beta.solana.com"
    else
        ok "Selected: ${best_rpc} (${best_time}ms)" >&2
        echo "$best_rpc"
    fi
}

RPC_URL=$(select_rpc)

# ── Check SOL balance ──────────────────────────────────────────────────────
check_balance() {
    local balance_response
    balance_response=$(curl -s -X POST "$RPC_URL" \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getBalance\",\"params\":[\"${PUBKEY}\"]}" \
        --max-time 10 2>/dev/null) || true

    if [ -n "$balance_response" ]; then
        local lamports
        lamports=$(echo "$balance_response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('result', {}).get('value', 0))
except:
    print(0)
" 2>/dev/null) || lamports=0

        if [ "$lamports" -gt 0 ] 2>/dev/null; then
            local sol
            sol=$(python3 -c "print(f'{${lamports} / 1_000_000_000:.6f}')")
            ok "Wallet balance: ${sol} SOL"

            if [ "$lamports" -lt 1000000 ]; then
                warn "Balance very low (<0.001 SOL). Mining needs ~0.001 SOL per block for tx fees."
                warn "Send some SOL to: ${PUBKEY}"
            fi
        else
            warn "Could not read balance or wallet is empty (0 SOL)"
            warn "Mining needs ~0.001 SOL per block for tx fees"
            warn "Send SOL to: ${PUBKEY}"
        fi
    else
        warn "Could not connect to RPC for balance check (will try mining anyway)"
    fi
}

# ── Show system info ────────────────────────────────────────────────────────
show_system_info() {
    local cores
    cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "?")
    local mem_gb
    mem_gb=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f", $1/1073741824}' || echo "?")

    echo -e "  ${DIM}System:${RESET}    ${cores} CPU cores, ${mem_gb}GB RAM"
}

# ── Print configuration ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Mining Configuration${RESET}"
echo -e "  ────────────────────────────────────────────────"
echo -e "  ${DIM}Wallet:${RESET}    ${PUBKEY}"
echo -e "  ${DIM}RPC:${RESET}       ${RPC_URL}"
echo -e "  ${DIM}Threads:${RESET}   ${THREADS} (0 = all cores)"
echo -e "  ${DIM}Max blocks:${RESET} ${MAX_BLOCKS} (0 = unlimited)"
echo -e "  ${DIM}CU limit:${RESET}  ${CU_LIMIT}"
echo -e "  ${DIM}Nonces/rnd:${RESET} ${MAX_NONCES} per thread"
show_system_info
echo -e "  ────────────────────────────────────────────────"
echo ""

check_balance

# ── Clone & build Equium ────────────────────────────────────────────────────
build_miner() {
    if [ ! -d "$EQUIUM_DIR" ]; then
        log "Cloning Equium repository..."
        git clone --depth 1 https://github.com/HannaPrints/equium.git "$EQUIUM_DIR"
    else
        log "Equium repository found, checking for updates..."
        local old_head new_head
        old_head=$(cd "$EQUIUM_DIR" && git rev-parse HEAD 2>/dev/null || echo "none")
        (cd "$EQUIUM_DIR" && git fetch --depth 1 origin master 2>/dev/null && git reset --hard origin/master 2>/dev/null) || true
        new_head=$(cd "$EQUIUM_DIR" && git rev-parse HEAD 2>/dev/null || echo "none")

        if [ "$old_head" != "$new_head" ]; then
            log "Source updated (${old_head:0:7} -> ${new_head:0:7}), will rebuild..."
            REBUILD=1
        fi
    fi

    local BINARY="$EQUIUM_DIR/target/release/equium-miner"

    if [ "$REBUILD" = "1" ] || [ ! -f "$BINARY" ]; then
        log "Building Equium CLI miner (release mode, LTO enabled)..."
        log "This may take a few minutes on first build..."
        (cd "$EQUIUM_DIR" && cargo build -p equium-cli-miner --release 2>&1)
        ok "Build complete!"
    else
        ok "Miner binary already built (use REBUILD=1 to force)"
    fi
}

build_miner

# ── Run the miner ───────────────────────────────────────────────────────────
BINARY="$EQUIUM_DIR/target/release/equium-miner"

if [ ! -f "$BINARY" ]; then
    err "Miner binary not found at: $BINARY"
    err "Try running with REBUILD=1"
    exit 1
fi

CMD=("$BINARY"
    --rpc-url "$RPC_URL"
    --keypair "$KEYPAIR_FILE"
    --cu-limit "$CU_LIMIT"
    --max-nonces-per-round "$MAX_NONCES"
)

if [ "$THREADS" != "0" ]; then
    CMD+=(--threads "$THREADS")
fi

if [ "$MAX_BLOCKS" != "0" ]; then
    CMD+=(--max-blocks "$MAX_BLOCKS")
fi

echo ""
log "Starting Equium miner..."
echo -e "  ${DIM}Press Ctrl+C to stop mining${RESET}"
echo ""

exec "${CMD[@]}"
