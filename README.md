# Equium ($EQM) Mining Script

One-script miner for [Equium](https://github.com/HannaPrints/equium) — a CPU-mineable Solana token with Bitcoin-style economics (21M cap, halvings, fair launch via Equihash PoW).

## Quick Start

```bash
git clone https://github.com/zaaaxx11/z.git
cd z/equium-miner

# Mine with your Solana private key
PRIVATE_KEY="your_base58_private_key" ./mine.sh
```

That's it. The script will:
1. Check all dependencies (Rust, Git, Python3, curl)
2. Auto-select the fastest public Solana RPC
3. Convert your private key to the required keypair format
4. Check your SOL balance for transaction fees
5. Clone and build the Equium miner from source
6. Start mining EQM tokens

### Monitor Mining Status

While mining is running, open another terminal and run:
```bash
./monitor.sh
```
This shows real-time stats: hashrate, CPU usage, tries, mined blocks, and EQM earned.

---

## Panduan Lengkap (Bahasa Indonesia)

### Step 1: Install Dependencies

```bash
# Install Rust (wajib, untuk compile miner)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# Install Git, Python3, curl (biasanya sudah ada)
# Ubuntu/Debian:
sudo apt update && sudo apt install -y git python3 curl
# macOS:
brew install git python3 curl
```

### Step 2: Clone Repo

```bash
git clone https://github.com/zaaaxx11/z.git
cd z/equium-miner
chmod +x mine.sh
```

### Step 3: Import Wallet (Private Key)

**Opsi A — Dari Phantom Wallet:**
1. Buka Phantom → Settings → Security & Privacy → Export Private Key
2. Copy string base58 (panjang, campuran huruf+angka)
3. Jalankan:
```bash
PRIVATE_KEY="paste_base58_key_disini" ./mine.sh
```

**Opsi B — Dari Solflare Wallet:**
1. Buka Solflare → Settings → Export Private Key
2. Copy string base58
3. Jalankan sama seperti Opsi A

**Opsi C — Buat Wallet Baru:**
```bash
# Install Solana CLI
sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"

# Generate keypair baru (catat address-nya, kirim SOL kesitu)
solana-keygen new --outfile ~/.config/solana/mining-wallet.json

# Jalankan mining pakai file keypair
PRIVATE_KEY="$HOME/.config/solana/mining-wallet.json" ./mine.sh
```

### Step 4: Jalankan Mining

**Paling simpel (auto RPC, semua CPU cores):**
```bash
PRIVATE_KEY="private_key_kamu" ./mine.sh
```

**Pilih RPC sendiri:**
```bash
# Gratis — Ankr
PRIVATE_KEY="key_kamu" RPC_URL="https://rpc.ankr.com/solana" ./mine.sh

# Gratis — dRPC
PRIVATE_KEY="key_kamu" RPC_URL="https://solana.drpc.org" ./mine.sh

# Recommended — Helius (daftar gratis di helius.dev)
PRIVATE_KEY="key_kamu" RPC_URL="https://mainnet.helius-rpc.com/?api-key=API_KEY_KAMU" ./mine.sh
```

**Custom thread + nonce budget (untuk optimasi):**
```bash
PRIVATE_KEY="key_kamu" \
  RPC_URL="https://rpc.ankr.com/solana" \
  THREADS=4 \
  MAX_NONCES=32768 \
  ./mine.sh
```

### Step 5: Pastikan Ada SOL

Mining butuh sedikit SOL (~0.001 per block) untuk transaction fees. Kirim minimal 0.01 SOL ke address wallet kamu sebelum mulai mining.

### Stop Mining

Tekan `Ctrl+C` untuk berhenti.

---

## Configuration

All configuration is done via environment variables:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PRIVATE_KEY` | **Yes** | — | Solana private key (base58 string or path to keypair JSON) |
| `RPC_URL` | No | Auto-select best | Solana RPC endpoint |
| `THREADS` | No | `0` (all cores) | Number of CPU threads |
| `MAX_BLOCKS` | No | `0` (unlimited) | Stop after N successful blocks |
| `CU_LIMIT` | No | `1400000` | Compute-unit limit per transaction |
| `MAX_NONCES` | No | `16384` | Max nonce attempts per round per thread |
| `REBUILD` | No | `0` | Set to `1` to force rebuild from source |

## Examples

### Basic CPU Mining (All Cores)

```bash
PRIVATE_KEY="5J3mBbAH58Z..." ./mine.sh
```

### Custom Thread Count

```bash
PRIVATE_KEY="5J3mBbAH58Z..." \
  THREADS=4 \
  ./mine.sh
```

### With Custom RPC + Higher Nonce Budget

```bash
PRIVATE_KEY="5J3mBbAH58Z..." \
  RPC_URL="https://rpc.ankr.com/solana" \
  THREADS=8 \
  MAX_NONCES=32768 \
  ./mine.sh
```

### Full Configuration Example

```bash
PRIVATE_KEY="5J3mBbAH58Z..." \
  RPC_URL="https://mainnet.helius-rpc.com/?api-key=YOUR_HELIUS_KEY" \
  THREADS=8 \
  MAX_BLOCKS=100 \
  CU_LIMIT=1400000 \
  MAX_NONCES=32768 \
  ./mine.sh
```

### Using Existing Keypair File

```bash
PRIVATE_KEY="$HOME/.config/solana/id.json" ./mine.sh
```

### Force Rebuild

```bash
PRIVATE_KEY="5J3mBbAH58Z..." REBUILD=1 ./mine.sh
```

## Private Key Input

The script accepts your Solana private key in multiple formats:

1. **Base58 string** (from Phantom/Solflare wallet export) — most common
   ```
   PRIVATE_KEY="5J3mBbAH58ZKt..." ./mine.sh
   ```

2. **Path to keypair JSON file** (from `solana-keygen new`)
   ```
   PRIVATE_KEY="/home/user/.config/solana/id.json" ./mine.sh
   ```

3. **JSON byte array**
   ```
   PRIVATE_KEY="[1,2,3,...,64]" ./mine.sh
   ```

### How to Export Private Key

**From Phantom Wallet:**
Settings → Security & Privacy → Export Private Key → Copy the base58 string

**From Solflare Wallet:**
Settings → Export Private Key → Copy the base58 string

**Generate New Keypair:**
```bash
solana-keygen new --outfile ~/.config/solana/mining-wallet.json
# Then use:
PRIVATE_KEY="$HOME/.config/solana/mining-wallet.json" ./mine.sh
```

## Public RPC Endpoints

The script auto-selects the fastest RPC if `RPC_URL` is not set. Available:

| Provider | URL | Notes |
|----------|-----|-------|
| Solana | `https://api.mainnet-beta.solana.com` | Aggressive rate limits |
| Ankr | `https://rpc.ankr.com/solana` | Good free tier |
| dRPC | `https://solana.drpc.org` | Decentralized RPC |
| Helius | `https://mainnet.helius-rpc.com/?api-key=KEY` | Best performance, free key at [helius.dev](https://www.helius.dev) |

For sustained mining, get a free Helius API key — public endpoints rate-limit aggressively under load.

## Why CPU Only? (No GPU)

Equium uses **Equihash (96,5)** — a memory-bound proof-of-work algorithm specifically designed to make GPUs NOT significantly faster than CPUs. This is intentional:

- The puzzle is **memory-bound**, not compute-bound
- A $40,000 GPU rig isn't meaningfully faster than your CPU
- This levels the playing field so anyone can mine
- More CPU threads = more parallelism = more hash attempts per second

### Performance Tips

- Use all available cores: `THREADS=0` (default)
- Increase nonce budget to reduce state-refetch overhead: `MAX_NONCES=32768` or `65536`
- Get a reliable RPC with low latency (Helius recommended)
- Ensure your system has enough RAM (Equihash is memory-intensive)
- Use a VPS close to Solana validators for lower tx latency

## Requirements

- **Rust/Cargo** — [Install Rust](https://rustup.rs)
- **Git**
- **Python 3** (for private key conversion)
- **curl** (for RPC health checks)
- **SOL** — Small amount (~0.001 SOL per block) for transaction fees

## How Mining Works

1. Your CPU guesses random nonces until it finds one that, combined with the current challenge, produces a valid Equihash solution below the target
2. The first valid solution submitted to Solana wins the block reward (currently 25 EQM)
3. Difficulty auto-adjusts every 60 blocks to maintain ~1 minute block times
4. Rewards halve over time (25 → 12.5 → 6.25 → ...)

## Security Features

- Keypair file (`.miner-keypair.json`) created with `chmod 600` — only owner can read
- Keypair file auto-deleted on script exit (trap on EXIT/INT/TERM)
- Private key passed via `sys.argv`, not shell interpolation (prevents injection)
- Base58 validation with proper character checking
- Solutions are bound to your wallet's public key — no front-running possible
- `.miner-keypair.json` excluded in `.gitignore`

## License

Apache-2.0 (same as Equium)

## Credits

Based on [Equium](https://github.com/HannaPrints/equium) by HannaPrints.
