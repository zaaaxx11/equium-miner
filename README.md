# Equium ($EQM) Mining Script

One-script miner for [Equium](https://github.com/HannaPrints/equium) — a CPU-mineable Solana token with Bitcoin-style economics (21M cap, halvings, fair launch via Equihash PoW).

## Quick Start

```bash
git clone https://github.com/YOUR_USERNAME/equium-miner.git
cd equium-miner

# Mine with your Solana private key
PRIVATE_KEY="your_base58_private_key" ./mine.sh
```

That's it. The script will:
1. Clone and build the Equium miner from source
2. Convert your private key to the required keypair format
3. Connect to a public Solana RPC
4. Start mining EQM tokens

## Configuration

All configuration is done via environment variables:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PRIVATE_KEY` | **Yes** | — | Solana private key (base58 string or path to keypair JSON) |
| `RPC_URL` | No | `https://api.mainnet-beta.solana.com` | Solana RPC endpoint |
| `THREADS` | No | `0` (all cores) | Number of CPU threads |
| `MAX_BLOCKS` | No | `0` (unlimited) | Stop after N successful blocks |
| `CU_LIMIT` | No | `1400000` | Compute-unit limit per transaction |
| `MAX_NONCES` | No | `4096` | Max nonce attempts per round per thread |

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

### With Custom RPC

```bash
PRIVATE_KEY="5J3mBbAH58Z..." \
  RPC_URL="https://rpc.ankr.com/solana" \
  THREADS=8 \
  ./mine.sh
```

### Full Configuration Example

```bash
PRIVATE_KEY="5J3mBbAH58Z..." \
  RPC_URL="https://mainnet.helius-rpc.com/?api-key=YOUR_HELIUS_KEY" \
  THREADS=8 \
  MAX_BLOCKS=100 \
  CU_LIMIT=1400000 \
  MAX_NONCES=8192 \
  ./mine.sh
```

### Using Existing Keypair File

```bash
PRIVATE_KEY="$HOME/.config/solana/id.json" ./mine.sh
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

These free public RPCs are available (rate-limited):

| Provider | URL | Notes |
|----------|-----|-------|
| Solana | `https://api.mainnet-beta.solana.com` | Default, aggressive rate limits |
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

To maximize mining performance on CPU:
- Use all available cores: `THREADS=0` (default)
- Get a reliable RPC with low latency
- Ensure your system has enough RAM (Equihash is memory-intensive)

## Requirements

- **Rust/Cargo** — [Install Rust](https://rustup.rs)
- **Git**
- **Python 3** (for private key conversion)
- **SOL** — Small amount (~0.001 SOL per block) for transaction fees

## How Mining Works

1. Your CPU guesses random nonces until it finds one that, combined with the current challenge, produces a valid Equihash solution below the target
2. The first valid solution submitted to Solana wins the block reward (currently 25 EQM)
3. Difficulty auto-adjusts every 60 blocks to maintain ~1 minute block times
4. Rewards halve over time (25 → 12.5 → 6.25 → ...)

## Security Notes

- The script creates a temporary keypair file (`.miner-keypair.json`) — keep it secure
- Solutions are bound to your wallet's public key — no front-running possible
- Never share your private key
- Add `.miner-keypair.json` to your `.gitignore`

## License

Apache-2.0 (same as Equium)

## Credits

Based on [Equium](https://github.com/HannaPrints/equium) by HannaPrints.
