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
#    RPC_URL         Solana RPC endpoint (default: public endpoint)
#    THREADS         Number of CPU threads (default: all cores)
#    MAX_BLOCKS      Stop after N blocks (0 = run forever, default: 0)
#    CU_LIMIT        Compute-unit limit per tx (default: 1400000)
#    MAX_NONCES      Max nonce attempts per round per thread (default: 4096)
#
#  EXAMPLES:
#    # Basic mining with all defaults
#    PRIVATE_KEY="5J3mBbAH..." ./mine.sh
#
#    # Custom RPC + 4 threads
#    PRIVATE_KEY="5J3mBbAH..." RPC_URL="https://rpc.ankr.com/solana" THREADS=4 ./mine.sh
#
#    # Using existing keypair file
#    PRIVATE_KEY="$HOME/.config/solana/id.json" ./mine.sh
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

# Public Solana RPC endpoints (free, rate-limited)
# Recommended: get a free Helius key at https://www.helius.dev for better limits
PUBLIC_RPCS=(
    "https://api.mainnet-beta.solana.com"
    "https://rpc.ankr.com/solana"
    "https://solana.drpc.org"
    "https://mainnet.helius-rpc.com/?api-key=YOUR_KEY"
)

RPC_URL="${RPC_URL:-https://api.mainnet-beta.solana.com}"
THREADS="${THREADS:-0}"
MAX_BLOCKS="${MAX_BLOCKS:-0}"
CU_LIMIT="${CU_LIMIT:-1400000}"
MAX_NONCES="${MAX_NONCES:-4096}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EQUIUM_DIR="${SCRIPT_DIR}/equium"
KEYPAIR_FILE="${SCRIPT_DIR}/.miner-keypair.json"

# ── Helpers ─────────────────────────────────────────────────────────────────
log()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()  { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
ok()   { echo -e "${GREEN}[OK]${RESET}    $*"; }

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
        if python3 -c "
import json, sys
with open('$key') as f:
    data = json.load(f)
assert isinstance(data, list) and len(data) == 64, 'Invalid keypair format'
" 2>/dev/null; then
            cp "$key" "$output"
            log "Using existing keypair file: $key"
            return 0
        fi
    fi

    # Case 2: JSON byte array string like [1,2,3,...,64]
    if echo "$key" | grep -qE '^\['; then
        if python3 -c "
import json, sys
data = json.loads('$key')
assert isinstance(data, list) and len(data) == 64
with open('$output', 'w') as f:
    json.dump(data, f)
" 2>/dev/null; then
            log "Converted JSON byte array to keypair file"
            return 0
        fi
    fi

    # Case 3: Base58 private key string (from Phantom/Solflare wallet export)
    python3 << PYEOF
import json, sys

ALPHABET = b'123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'

def b58decode(s):
    """Decode a Base58-encoded string to bytes."""
    n = 0
    for c in s.encode():
        n = n * 58 + ALPHABET.index(c)
    # Convert to bytes
    result = []
    while n > 0:
        result.append(n & 0xff)
        n >>= 8
    result.reverse()
    # Preserve leading zeros
    pad = 0
    for c in s.encode():
        if c == ALPHABET[0]:
            pad += 1
        else:
            break
    return b'\x00' * pad + bytes(result)

try:
    key_str = """${key}""".strip()
    key_bytes = b58decode(key_str)

    if len(key_bytes) == 64:
        # Full keypair (secret + public)
        keypair = list(key_bytes)
    elif len(key_bytes) == 32:
        # Secret key only — cannot derive public key without nacl
        # Try importing nacl
        try:
            import nacl.signing
            signing_key = nacl.signing.SigningKey(key_bytes)
            verify_key = signing_key.verify_key
            keypair = list(key_bytes) + list(bytes(verify_key))
        except ImportError:
            print("ERROR: 32-byte private key provided but 'pynacl' is not installed.", file=sys.stderr)
            print("Install it with: pip3 install pynacl", file=sys.stderr)
            print("Or export the full 64-byte keypair from your wallet.", file=sys.stderr)
            sys.exit(1)
    else:
        print(f"ERROR: Decoded key is {len(key_bytes)} bytes. Expected 64 (full keypair) or 32 (secret only).", file=sys.stderr)
        sys.exit(1)

    with open("${output}", "w") as f:
        json.dump(keypair, f)

    print(f"Converted base58 private key to keypair file ({len(key_bytes)} bytes)")

except Exception as e:
    print(f"ERROR: Failed to convert private key: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

log "Converting private key..."
convert_private_key "$PRIVATE_KEY" "$KEYPAIR_FILE"
ok "Keypair file ready"

# Extract public key for display
PUBKEY=$(python3 -c "
import json
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
with open('${KEYPAIR_FILE}') as f:
    kp = json.load(f)
print(b58encode(bytes(kp[32:])))
")

# ── Print configuration ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Mining Configuration${RESET}"
echo -e "  ────────────────────────────────────────────────"
echo -e "  ${DIM}Wallet:${RESET}    ${PUBKEY}"
echo -e "  ${DIM}RPC:${RESET}       ${RPC_URL}"
echo -e "  ${DIM}Threads:${RESET}   ${THREADS} (0 = all cores)"
echo -e "  ${DIM}Max blocks:${RESET} ${MAX_BLOCKS} (0 = unlimited)"
echo -e "  ${DIM}CU limit:${RESET}  ${CU_LIMIT}"
echo -e "  ────────────────────────────────────────────────"
echo ""

# ── Check dependencies ──────────────────────────────────────────────────────
check_deps() {
    local missing=()

    if ! command -v cargo &>/dev/null; then
        missing+=("rust/cargo")
    fi
    if ! command -v git &>/dev/null; then
        missing+=("git")
    fi
    if ! command -v python3 &>/dev/null; then
        missing+=("python3")
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
            esac
        done
        echo ""
        exit 1
    fi

    ok "All dependencies found"
}

check_deps

# ── Clone & build Equium ────────────────────────────────────────────────────
build_miner() {
    if [ ! -d "$EQUIUM_DIR" ]; then
        log "Cloning Equium repository..."
        git clone https://github.com/HannaPrints/equium.git "$EQUIUM_DIR"
    else
        log "Equium repository found, pulling latest..."
        (cd "$EQUIUM_DIR" && git pull --ff-only 2>/dev/null || true)
    fi

    local BINARY="$EQUIUM_DIR/target/release/equium-miner"

    if [ ! -f "$BINARY" ]; then
        log "Building Equium CLI miner (release mode)..."
        log "This may take a few minutes on first build..."
        (cd "$EQUIUM_DIR" && cargo build -p equium-cli-miner --release)
        ok "Build complete!"
    else
        ok "Miner binary already built"
    fi
}

build_miner

# ── Run the miner ───────────────────────────────────────────────────────────
BINARY="$EQUIUM_DIR/target/release/equium-miner"

if [ ! -f "$BINARY" ]; then
    err "Miner binary not found at: $BINARY"
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
echo -e "  ${DIM}Press Ctrl+C to stop${RESET}"
echo ""

exec "${CMD[@]}"
