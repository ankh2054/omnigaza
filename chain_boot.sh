#!/usr/bin/env bash
set -euo pipefail

# ---- settings you can tweak ----
NODE_NAME="devnet"
CORE_SYMBOL="SYS"
WORKDIR="${PWD}/manual-node"
CONFIG_DIR="${WORKDIR}/config"
DATA_DIR="${WORKDIR}/data"
mkdir -p "$CONFIG_DIR" "$DATA_DIR"

echo "CONFIG_DIR: $CONFIG_DIR"
echo "DATA_DIR: $DATA_DIR"

# ---- Build custom docker image ----
IMAGE_NAME="omnigaza-devnet"
echo "Building custom devnet image..."
docker build --platform=linux/amd64 -t "$IMAGE_NAME" .

# Check if build succeeded
if [ $? -ne 0 ]; then
  echo "❌ Docker build failed!"
  exit 1
fi
echo "✅ Docker image built successfully: $IMAGE_NAME"

# ---- Create genesis.json with higher CPU/NET limits ----
cat > "${WORKDIR}/genesis.json" <<EOF
{
  "initial_timestamp": "2025-09-30T08:55:11.000",
  "initial_key": "EOS7MRd8aJco8YfWxhRU5nqrk9x4GSiVgJBbC7uyuxg67S1zPuVft",
  "initial_configuration": {
    "max_block_net_usage": 1048576,
    "target_block_net_usage_pct": 1000,
    "max_transaction_net_usage": 524288,
    "base_per_transaction_net_usage": 12,
    "net_usage_leeway": 500,
    "context_free_discount_net_usage_num": 20,
    "context_free_discount_net_usage_den": 100,
    "max_block_cpu_usage": 2000000,
    "target_block_cpu_usage_pct": 1000,
    "max_transaction_cpu_usage": 500000,
    "min_transaction_cpu_usage": 100,
    "max_transaction_lifetime": 3600,
    "deferred_trx_expiration_window": 600,
    "max_transaction_delay": 3888000,
    "max_inline_action_size": 4096,
    "max_inline_action_depth": 4,
    "max_authority_depth": 6
  }
}
EOF

# ---- Create config.ini ----
cat > "${CONFIG_DIR}/config.ini" <<EOF
wasm-runtime = eos-vm-jit
abi-serializer-max-time-ms = 2000
chain-state-db-size-mb = 65536
contracts-console = true
http-server-address = 0.0.0.0:8888
p2p-listen-endpoint = 0.0.0.0:9876
verbose-http-errors = true
agent-name = devnet
producer-name = eosio
enable-stale-production = true
resource-monitor-not-shutdown-on-threshold-exceeded = true
http-validate-host = false
plugin = eosio::chain_api_plugin
plugin = eosio::http_plugin
plugin = eosio::producer_plugin
plugin = eosio::producer_api_plugin
# dev key for eosio (only for local/dev)
signature-provider = EOS7MRd8aJco8YfWxhRU5nqrk9x4GSiVgJBbC7uyuxg67S1zPuVft=KEY:5JADG9WEjHyqMgcCb3i7Zf8ZZSZzwppuj4hHMCQZnah43uSKdiW
EOF

# ---- Stop existing container if running ----
docker stop "${NODE_NAME}" 2>/dev/null || true
docker rm "${NODE_NAME}" 2>/dev/null || true

# ---- Clean old database if it exists ----
if [ -d "${DATA_DIR}" ]; then
  echo "Clearing old database..."
  rm -rf "${DATA_DIR}"/*
fi

# ---- Start fresh chain with genesis.json (first run only) ----
echo "Starting nodeos with genesis.json..."
docker run -d --name "${NODE_NAME}" --restart unless-stopped \
  --platform linux/amd64 \
  -p 8888:8888 -p 9876:9876 \
  -v "${DATA_DIR}":/app/data \
  -v "${CONFIG_DIR}":/app/config \
  -v "${WORKDIR}/genesis.json":/app/genesis.json \
  "$IMAGE_NAME" \
  bash -c "keosd --unlock-timeout 999999999 --http-server-address 127.0.0.1:8900 & nodeos --data-dir /app/data --config-dir /app/config --genesis-json /app/genesis.json"

# ---- Wait for API to be ready ----
echo "Waiting for HTTP server to be ready..."
until curl -s http://127.0.0.1:8888/v1/chain/get_info >/dev/null 2>&1; do 
  sleep 1
done

# ---- Show chain info ----
echo "Chain info:"
curl -s http://127.0.0.1:8888/v1/chain/get_info | jq .

# ---- Bootstrap system contracts ----
echo "Starting system contract bootstrap..."

# Start keosd and create wallet
echo "Setting up wallet..."
docker exec "$NODE_NAME" rm -rf /root/eosio-wallet/./default.wallet
sleep 1

# Create devnet wallet and import keys
echo "Creating devnet wallet and importing keys..."
docker exec "$NODE_NAME" cleos wallet create --file /tmp/wallet.pw 
docker exec "$NODE_NAME" cleos wallet import --private-key 5JADG9WEjHyqMgcCb3i7Zf8ZZSZzwppuj4hHMCQZnah43uSKdiW

# Preactivate protocol features
echo "Preactivating protocol features..."
docker exec "$NODE_NAME" curl -X POST http://127.0.0.1:8888/v1/producer/schedule_protocol_feature_activations \
  -H "Content-Type: application/json" \
  -d '{"protocol_features_to_activate": ["0ec7e080177b2c02b278d5088611686b49d739925a92d9bfcacd7fc6b74053bd"]}'

sleep 5

# Deploy eosio.boot contract
echo "Deploying eosio.boot contract..."
docker exec "$NODE_NAME" cleos set contract eosio /app/reference-contracts/build/contracts/eosio.boot

# Create system accounts
echo "Creating system accounts..."
docker exec "$NODE_NAME" cleos  create account eosio eosio.msig  EOS7MRd8aJco8YfWxhRU5nqrk9x4GSiVgJBbC7uyuxg67S1zPuVft
docker exec "$NODE_NAME" cleos  create account eosio eosio.token EOS7MRd8aJco8YfWxhRU5nqrk9x4GSiVgJBbC7uyuxg67S1zPuVft
docker exec "$NODE_NAME" cleos  create account eosio eosio.bpay EOS7MRd8aJco8YfWxhRU5nqrk9x4GSiVgJBbC7uyuxg67S1zPuVft
docker exec "$NODE_NAME" cleos  create account eosio eosio.names EOS7MRd8aJco8YfWxhRU5nqrk9x4GSiVgJBbC7uyuxg67S1zPuVft
docker exec "$NODE_NAME" cleos  create account eosio eosio.ram EOS7MRd8aJco8YfWxhRU5nqrk9x4GSiVgJBbC7uyuxg67S1zPuVft
docker exec "$NODE_NAME" cleos  create account eosio eosio.ramfee EOS7MRd8aJco8YfWxhRU5nqrk9x4GSiVgJBbC7uyuxg67S1zPuVft
docker exec "$NODE_NAME" cleos  create account eosio eosio.saving EOS7MRd8aJco8YfWxhRU5nqrk9x4GSiVgJBbC7uyuxg67S1zPuVft
docker exec "$NODE_NAME" cleos  create account eosio eosio.stake EOS7MRd8aJco8YfWxhRU5nqrk9x4GSiVgJBbC7uyuxg67S1zPuVft
docker exec "$NODE_NAME" cleos  create account eosio eosio.vpay EOS7MRd8aJco8YfWxhRU5nqrk9x4GSiVgJBbC7uyuxg67S1zPuVft
docker exec "$NODE_NAME" cleos  create account eosio eosio.rex EOS7MRd8aJco8YfWxhRU5nqrk9x4GSiVgJBbC7uyuxg67S1zPuVft

# Get available protocol features and activate them FIRST
echo "Activating protocol features..."
# Activate protocol features (explicit hashes, ordered)
docker exec "$NODE_NAME" cleos push action eosio activate '["c3a6138c5061cf291310887c0b5c71fcaffeab90d5deb50d3b9e687cead45071"]' -p eosio@active  # ACTION_RETURN_VALUE
docker exec "$NODE_NAME" cleos push action eosio activate '["d528b9f6e9693f45ed277af93474fd473ce7d831dae2180cca35d907bd10cb40"]' -p eosio@active  # CONFIGURABLE_WASM_LIMITS2
docker exec "$NODE_NAME" cleos push action eosio activate '["5443fcf88330c586bc0e5f3dee10e7f63c76c00249c87fe4fbf7f38c082006b4"]' -p eosio@active  # BLOCKCHAIN_PARAMETERS
docker exec "$NODE_NAME" cleos push action eosio activate '["f0af56d2c5a48d60a4a5b5c903edfb7db3a736a94ed589d0b797df33ff9d3e1d"]' -p eosio@active  # GET_SENDER
docker exec "$NODE_NAME" cleos push action eosio activate '["2652f5f96006294109b3dd0bbde63693f55324af452b799ee137a81a905eed25"]' -p eosio@active  # FORWARD_SETCODE
docker exec "$NODE_NAME" cleos push action eosio activate '["8ba52fe7a3956c5cd3a656a3174b931d3bb2abb45578befc59f283ecd816a405"]' -p eosio@active  # ONLY_BILL_FIRST_AUTHORIZER
docker exec "$NODE_NAME" cleos push action eosio activate '["ad9e3d8f650687709fd68f4b90b41f7d825a365b02c23a636cef88ac2ac00c43"]' -p eosio@active  # RESTRICT_ACTION_TO_SELF
docker exec "$NODE_NAME" cleos push action eosio activate '["68dcaa34c0517d19666e6b33add67351d8c5f69e999ca1e37931bc410a297428"]' -p eosio@active  # DISALLOW_EMPTY_PRODUCER_SCHEDULE
docker exec "$NODE_NAME" cleos push action eosio activate '["e0fb64b1085cc5538970158d05a009c24e276fb94e1a0bf6a528b48fbc4ff526"]' -p eosio@active  # FIX_LINKAUTH_RESTRICTION
docker exec "$NODE_NAME" cleos push action eosio activate '["ef43112c6543b88db2283a2e077278c315ae2c84719a8b25f25cc88565fbea99"]' -p eosio@active  # REPLACE_DEFERRED
docker exec "$NODE_NAME" cleos push action eosio activate '["4a90c00d55454dc5b059055ca213579c6ea856967712a56017487886a4d4cc0f"]' -p eosio@active  # NO_DUPLICATE_DEFERRED_ID
docker exec "$NODE_NAME" cleos push action eosio activate '["1a99a59d87e06e09ec5b028a9cbb7749b4a5ad8819004365d02dc4379a8b7241"]' -p eosio@active  # ONLY_LINK_TO_EXISTING_PERMISSION
docker exec "$NODE_NAME" cleos push action eosio activate '["4e7bf348da00a945489b2a681749eb56f5de00b900014e137ddae39f48f69d67"]' -p eosio@active  # RAM_RESTRICTIONS
docker exec "$NODE_NAME" cleos push action eosio activate '["4fca8bd82bbd181e714e283f83e1b45d95ca5af40fb89ad3977b653c448f78c2"]' -p eosio@active  # WEBAUTHN_KEY
docker exec "$NODE_NAME" cleos push action eosio activate '["299dcb6af692324b899b39f16d5a530a33062804e41f09dc97e9f156b4476707"]' -p eosio@active  # WTMSIG_BLOCK_SIGNATURES
docker exec "$NODE_NAME" cleos push action eosio activate '["bcd2a26394b36614fd4894241d3c451ab0f6fd110958c3423073621a70826e99"]' -p eosio@active  # GET_CODE_HASH
docker exec "$NODE_NAME" cleos push action eosio activate '["35c2186cc36f7bb4aeaf4487b36e57039ccf45a9136aa856a5d569ecca55ef2b"]' -p eosio@active  # GET_BLOCK_NUM
docker exec "$NODE_NAME" cleos push action eosio activate '["6bcb40a24e49c26d0a60513b6aeb8551d264e4717f306b81a37a5afb3b47cedc"]' -p eosio@active  # CRYPTO_PRIMITIVES
docker exec "$NODE_NAME" cleos push action eosio activate '["63320dd4a58212e4d32d1f58926b73ca33a247326c2a5e9fd39268d2384e011a"]' -p eosio@active  # BLS_PRIMITIVES2
docker exec "$NODE_NAME" cleos push action eosio activate '["fce57d2331667353a0eac6b4209b67b843a7262a848af0a49a6e2fa9f6584eb4"]' -p eosio@active  # DISABLE_DEFERRED_TRXS_STAGE_1
docker exec "$NODE_NAME" cleos push action eosio activate '["09e86cb0accf8d81c9e85d34bea4b925ae936626d00c984e4691186891f5bc16"]' -p eosio@active  # DISABLE_DEFERRED_TRXS_STAGE_2
docker exec "$NODE_NAME" cleos push action eosio activate '["cbe0fafc8fcc6cc998395e9b6de6ebd94644467b1b4a97ec126005df07013c52"]' -p eosio@active  # SAVANNA


# Deploy contracts AFTER activating features
echo "Deploying system contracts..."
docker exec "$NODE_NAME" cleos  set contract eosio.msig /app/reference-contracts/build/contracts/eosio.msig
docker exec "$NODE_NAME" cleos  set contract eosio.token /app/reference-contracts/build/contracts/eosio.token
docker exec "$NODE_NAME" cleos  set contract eosio /app/reference-contracts/build/contracts/eosio.system

# Setup token
echo "Setting up token system..."
docker exec "$NODE_NAME" cleos push action eosio.token create '["eosio","10000000000.0000 SYS"]' -p eosio.token
docker exec "$NODE_NAME" cleos push action eosio.token issue '["eosio","1000000000.0000 SYS","initial supply"]' -p eosio
docker exec "$NODE_NAME" cleos push action eosio init '["0","4,SYS"]' -p eosio

echo
echo "✅ Devnet fully bootstrapped!"
echo "HTTP: http://localhost:8888  P2P: 9876"
echo "Data dir: $DATA_DIR"
echo "Config dir: $CONFIG_DIR"
echo "Genesis: ${WORKDIR}/genesis.json"
echo
echo "To restart without genesis (after first run):"
echo "docker stop $NODE_NAME && docker rm $NODE_NAME"
echo "docker run -d --name $NODE_NAME --restart unless-stopped \\"
echo "  --platform linux/amd64 \\"
echo "  -p 8888:8888 -p 9876:9876 \\"
echo "  -v $DATA_DIR:/app/data \\"
echo "  -v $CONFIG_DIR:/app/config \\"
echo "  $IMAGE_NAME \\"
echo "  bash -c \"keosd --unlock-timeout 999999999 --http-server-address 127.0.0.1:8900 & nodeos --data-dir /app/data --config-dir /app/config\""
