# Blockscout Package

The Blockscout package is a plug-and-play explorer bundle that lets you deploy Blockscout services—including backend, frontend, and smart contract verifier—within any [Kurtosis](https://docs.kurtosis.com)  environment, supporting both Ethereum-based and Optimism (OP Stack) chains. 
* Drop it into any EVM dev-net for a full explorer UI in seconds
* or run it standalone for a local explorer setup.

## Package Components

The package includes:
- Blockscout backend service
- Smart contract verification service
- Frontend interface 
- PostgreSQL database for storage

## Exposed Ports

| Service | Default Port | Protocol |
|---------|-------------|----------|
| Blockscout Backend | 4000 | HTTP |
| Contract Verifier | 8050 | HTTP |
| Frontend | 3000 | HTTP |
| PostgreSQL | 5432 | TCP |


## Default Configuration

The package includes defaults for:
- Service names
- Ports
- CPU & Memory allocations
- Container images
- Blockchain network parameters (Ethereum, Optimism)

All values can be overridden via general_args, ethereum_args, and optimism_args.

## Basic Usage

You call the run function with:
- plan: Kurtosis execution plan
- general_args: Optional overrides for the defaults
- ethereum_args: Ethereum-specific configuration
- optimism_args: Optimism-specific configuration
- persistent: Whether to persist data across runs
- node_selectors: Optional Kubernetes node selectors
- port_publisher: Optional Kurtosis port publisher

```python
blockscout_output = blockscout.run(
    plan,
    general_args={...},      
    ethereum_args={...},    
    optimism_args={...},    
    persistent=False,         
    node_selectors={},       
    port_publisher=None,     
)
```

## Ethereum Configuration Example

```python
# Ethereum configuration
ethereum_args = {
    "rpc_url": "http://geth:8545",        # Required: Execution layer RPC URL
    "ws_url": "ws://geth:8546",           # Optional: WebSocket URL
    "client_name": "geth",                # Optional: Client name (geth, erigon, etc.)
    "extra_env_vars": {                   # Optional: Additional environment variables
        "NETWORK": "MyNetwork",
        "SUBNETWORK": "MyNetwork"
    },
    "frontend_env_vars": {                # Optional: Frontend-specific env vars
        "NEXT_PUBLIC_NETWORK_NAME": "MyNetwork"
    }
}

blockscout_output = blockscout.run(
    plan,
    general_args={
        "network_name": "MyNetwork",
        "network_id": "1337",
        "coin": "ETH",
        "is_testnet": "true",
        "blockscout_image": "ghcr.io/blockscout/blockscout:v7.0.2",
        "include_frontend": True,
    },
    ethereum_args=ethereum_args,
)
```

## Optimism Configuration Example

```python
# Optimism configuration
optimism_args = {
    "optimism_enabled": True,
    "l1_rpc_url": "http://l1-node:8545",          # Required: L1 RPC URL
    "l2_rpc_url": "http://l2-node:8545",          # Required: L2 RPC URL
    "network_name": "OptimismTestnet",            # Optional: Network name
    "portal_address": "0x...",                    # Required: Portal contract address
    "l1_deposit_start_block": "0",                # Required: L1 deposit start block
    "l1_withdrawals_start_block": "0",            # Required: L1 withdrawals start block
    "output_oracle_address": "0x..."              # Required: Output oracle address
}

blockscout_output = blockscout.run(
    plan,
    general_args={
        "network_name": "OptimismTestnet",
        "network_id": "420",
        "coin": "opETH",
        "is_testnet": "true",
    },
    optimism_args=optimism_args,
)
```

## Accessing Services

The function returns URLs and service objects for the deployed components:

```python
blockscout_url = blockscout_output["blockscout_url"]           # Backend API URL
verification_url = blockscout_output["verification_url"]       # Verification service URL
frontend_url = blockscout_output["frontend_url"]               # Frontend URL (if enabled)
```

