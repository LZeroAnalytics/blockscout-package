utils = import_module("./src/utils.star")
postgres = import_module("github.com/kurtosis-tech/postgres-package/main.star")

# Default values for Blockscout deployment
DEFAULT_VALUES = {
    # Service names
    "service_name_blockscout": "blockscout",
    "service_name_blockscout_verifier": "blockscout-verifier",
    "service_name_blockscout_frontend": "blockscout-frontend",
    
    # Port configurations
    "http_port_id": "http",
    "http_port_number": 4000,
    "http_port_number_verif": 8050,
    "http_port_number_frontend": 3001,
    
    # Resource allocations
    "blockscout_min_cpu": 100,
    "blockscout_max_cpu": 1000,
    "blockscout_min_memory": 1024,
    "blockscout_max_memory": 2048,
    
    "blockscout_verifier_min_cpu": 10,
    "blockscout_verifier_max_cpu": 1000,
    "blockscout_verifier_min_memory": 10,
    "blockscout_verifier_max_memory": 1024,
    
    # Image defaults
    "postgres_image": "library/postgres:alpine",
    "blockscout_image": "blockscout/blockscout:latest",
    "blockscout_optimism_image": "blockscout/blockscout-optimism:6.8.0",
    "blockscout_verifier_image": "ghcr.io/blockscout/smart-contract-verifier:latest",
    "blockscout_frontend_image": "ghcr.io/blockscout/frontend:latest",
    
    # Ethereum defaults
    "network_name": "Bloctopus",
    "network_id": "31337",
    "coin": "ETH",
    "is_testnet": "true",
    "has_beacon_chain": "true",
    
    # Optimism defaults
    "optimism_enabled": False,
    "optimism_chain_type": "optimism",
    "optimism_l1_batch_inbox": "0xff00000000000000000000000000000000042069",
    "optimism_l1_batch_submitter": "0x776463f498A63a42Ac1AFc7c64a4e5A9ccBB4d32",
    "optimism_l2_message_passer_contract": "0xC0D3C0d3C0d3c0d3C0d3C0D3c0D3c0d3c0D30016",

    # General defaults
    "wallet_connect_id": "",
    "api_protocol": "http",
    "ws_protocol": "ws",
    "app_host": "127.0.0.1",
}

def run(
    plan,
    general_args={},
    ethereum_args={},
    optimism_args={},
    persistent=False,
    node_selectors={},
    port_publisher=None,
):
    """
    Runs Blockscout with the given configuration options
    
    Args:
        plan: The Kurtosis execution plan
        general_args: General configuration for Blockscout (overrides defaults)
        ethereum_args: Ethereum-specific configuration (required if not using Optimism)
        optimism_args: Optimism-specific configuration (required if using Optimism)
        persistent: Whether to persist data across runs
        node_selectors: Kubernetes node selectors for service placement
        port_publisher: Port publisher for service ports
    
    Returns:
        Dictionary containing URLs for accessing the deployed services
    """
    config = dict(DEFAULT_VALUES)
    
    # Override defaults with user-provided general args
    for key, value in general_args.items():
        config[key] = value
    
    optimism_enabled = optimism_args.get("optimism_enabled", config["optimism_enabled"])
    
    postgres_output = _run_postgres(plan, config, persistent, node_selectors)
    
    verifier_service = _create_verification_service(plan, config, node_selectors, port_publisher)
    verifier_url = "http://{}:{}".format(
        verifier_service.hostname,
        verifier_service.ports[config["http_port_id"]].number,
    )    

    if optimism_enabled:
        blockscout_service = _create_optimism_backend(
            plan, config, postgres_output, verifier_url, optimism_args, node_selectors, port_publisher
        )
    else:
        blockscout_service = _create_ethereum_backend(
            plan, config, postgres_output, verifier_url, ethereum_args, node_selectors, port_publisher
        )
    
    blockscout_url = "http://{}:{}".format(
        blockscout_service.hostname,
        blockscout_service.ports[config["http_port_id"]].number,
    )
    
    frontend_url = None
    if config.get("include_frontend", True):
        frontend_service = _create_frontend_service(
            plan, config, blockscout_service, ethereum_args, node_selectors, port_publisher
        )
        frontend_url = "http://{}:{}".format(
            frontend_service.hostname,
            frontend_service.ports[config["http_port_id"]].number,
        )    

    return {
        "blockscout_url": blockscout_url,
        "verification_url": verifier_url,
        "frontend_url": frontend_url,
        "blockscout_service": blockscout_service,
        "verification_service": verifier_service,
    }

def _run_postgres(plan, config, persistent, node_selectors):
    service_name = "{}-postgres".format(config["service_name_blockscout"])
    
    postgres_output = postgres.run(
        plan,
        service_name=service_name,
        database="blockscout",
        extra_configs=["max_connections=1000"],
        persistent=persistent,
        node_selectors=node_selectors,
        image=config["postgres_image"],
    )
    
    return postgres_output

def _create_verification_service(plan, config, node_selectors, port_publisher):
    verifier_service_name = config['service_name_blockscout_verifier']
    
    verifier_used_ports = {
        config["http_port_id"]: utils.new_port_spec(
            config["http_port_number_verif"],
            utils.TCP_PROTOCOL,
            utils.HTTP_APPLICATION_PROTOCOL,
        )
    }
    
    public_ports = {}
    if "port_publisher" in config and config["port_publisher"]:
        public_ports = {"http": verifier_used_ports}
    
    
    verifier_config = ServiceConfig(
        image=config["blockscout_verifier_image"],
        ports=verifier_used_ports,
        public_ports=public_ports,
        env_vars={
            "SMART_CONTRACT_VERIFIER__SERVER__HTTP__ADDR": "0.0.0.0:{}".format(config["http_port_number_verif"])  
        },
        min_cpu=config["blockscout_verifier_min_cpu"],
        max_cpu=config["blockscout_verifier_max_cpu"],
        min_memory=config["blockscout_verifier_min_memory"],
        max_memory=config["blockscout_verifier_max_memory"],
        node_selectors=node_selectors,
    )
    
    verifier_service = plan.add_service(verifier_service_name, verifier_config)
    return verifier_service

def _create_ethereum_backend(plan, config, postgres_output, verif_url, ethereum_args, node_selectors, port_publisher):
    service_name = config["service_name_blockscout"]
    
    el_client_rpc_url = ethereum_args.get("rpc_url")
    el_client_ws_url = ethereum_args.get("ws_url")
    el_client_name = ethereum_args.get("client_name", "geth")
    
    if not el_client_rpc_url:
        fail("Ethereum RPC URL must be provided in ethereum_args")
    
    database_url = "postgresql://{}:{}@{}:{}/{}".format(
        postgres_output.user,
        postgres_output.password,
        postgres_output.service.hostname,
        postgres_output.port.number,
        postgres_output.database,
    )

    used_ports = {
        config["http_port_id"]: utils.new_port_spec(
            config["http_port_number"],
            utils.TCP_PROTOCOL,
            utils.HTTP_APPLICATION_PROTOCOL,
        )
    }
    
    public_ports = {}
    if "port_publisher" in config and config["port_publisher"]:
        public_ports = {"http": used_ports}
    

    env_vars = {
        "ETHEREUM_JSONRPC_VARIANT": "erigon" if el_client_name in ["erigon", "reth"] else el_client_name,
        "DATABASE_URL": database_url,
        "DATABASE_POOL_SIZE": "80",
        "ETHEREUM_JSONRPC_HTTP_URL": el_client_rpc_url,
        "ETHEREUM_JSONRPC_TRACE_URL": el_client_rpc_url,
        "ETHEREUM_JSONRPC_WS_URL": el_client_ws_url,
        "NETWORK": config["network_name"],
        "SUBNETWORK": config["network_name"],
        "COIN": config["coin"],
        "SECRET_KEY_BASE": "56NtB48ear7+wMSf0IQuWDAAazhpb31qyc7GiyspBP2vh7t5zlCsF5QDv76chXeN",
        "ECTO_USE_SSL": "false",
        "API_V2_ENABLED": "true",
        "INDEXER_DISABLE_PENDING_TRANSACTIONS_FETCHER": "true",

        "MICROSERVICE_SC_VERIFIER_ENABLED": "true",
        "MICROSERVICE_SC_VERIFIER_URL": verif_url,
        "MICROSERVICE_SC_VERIFIER_TYPE": "sc_verifier",
        "PORT": str(config["http_port_number"]),
        "SMART_CONTRACT_VERIFIER__SERVER__HTTP__ADDR": "0.0.0.0:{}".format(config["http_port_number_verif"]),
        "SMART_CONTRACT_VERIFIER__FETCHERS__ZKSYNC__ENABLED": "false",
    }
    
    if "extra_env_vars" in ethereum_args:
        for key, value in ethereum_args["extra_env_vars"].items():
            env_vars[key] = value
    
    backend_config = ServiceConfig(
        image=config["blockscout_image"],
        ports=used_ports,
        public_ports=public_ports,
        cmd=[
            "/bin/sh",
            "-c",
            'bin/blockscout eval "Elixir.Explorer.ReleaseTasks.create_and_migrate()" && bin/blockscout start',
        ],
        env_vars=env_vars,
        min_cpu=config["blockscout_min_cpu"],
        max_cpu=config["blockscout_max_cpu"],
        min_memory=config["blockscout_min_memory"],
        max_memory=config["blockscout_max_memory"],
        node_selectors=node_selectors,
    )
    
    blockscout_service = plan.add_service(service_name, backend_config)
    return blockscout_service

def _create_optimism_backend(plan, config, postgres_output, verif_url, optimism_args, node_selectors, port_publisher):
    service_name = config["service_name_blockscout"]
    
    l1_rpc_url = optimism_args.get("l1_rpc_url")
    l2_rpc_url = optimism_args.get("l2_rpc_url")
    network_name = optimism_args.get("network_name", config["network_name"])
    
    if not l1_rpc_url or not l2_rpc_url:
        fail("L1 and L2 RPC URLs must be provided in optimism_args")
    
    database_url = "postgresql://{}:{}@{}:{}/{}".format(
        postgres_output.user,
        postgres_output.password,
        postgres_output.service.hostname,
        postgres_output.port.number,
        postgres_output.database,
    )

    used_ports = {
        config["http_port_id"]: utils.new_port_spec(
            config["http_port_number"],
            utils.TCP_PROTOCOL,
            utils.HTTP_APPLICATION_PROTOCOL,
        )
    }

    public_ports = {}
    if "port_publisher" in config and config["port_publisher"]:
        public_ports = {"http": used_ports}
    
    env_vars = {
        "ETHEREUM_JSONRPC_VARIANT": "geth",
        "ETHEREUM_JSONRPC_HTTP_URL": l2_rpc_url,
        "ETHEREUM_JSONRPC_TRACE_URL": l2_rpc_url,
        "DATABASE_URL": database_url,
        "COIN": "opETH",
        "MICROSERVICE_SC_VERIFIER_ENABLED": "true",
        "MICROSERVICE_SC_VERIFIER_URL": verif_url,
        "MICROSERVICE_SC_VERIFIER_TYPE": "sc_verifier",
        "INDEXER_DISABLE_PENDING_TRANSACTIONS_FETCHER": "true",
        "ECTO_USE_SSL": "false",
        "NETWORK": network_name,
        "SUBNETWORK": network_name,
        "API_V2_ENABLED": "true",
        "PORT": str(config["http_port_number"]),
        "SECRET_KEY_BASE": "56NtB48ear7+wMSf0IQuWDAAazhpb31qyc7GiyspBP2vh7t5zlCsF5QDv76chXeN",
        
        # Optimism-specific configs
        "CHAIN_TYPE": config["optimism_chain_type"],
        "INDEXER_OPTIMISM_L1_RPC": l1_rpc_url,
        "INDEXER_OPTIMISM_L1_BATCH_INBOX": config["optimism_l1_batch_inbox"],
        "INDEXER_OPTIMISM_L1_BATCH_SUBMITTER": config["optimism_l1_batch_submitter"],
        "INDEXER_OPTIMISM_L1_BATCH_BLOCKSCOUT_BLOBS_API_URL": verif_url + "/blobs",
        "INDEXER_OPTIMISM_L1_BATCH_BLOCKS_CHUNK_SIZE": "4",
        "INDEXER_OPTIMISM_L2_BATCH_GENESIS_BLOCK_NUMBER": "0",
        "INDEXER_OPTIMISM_L1_OUTPUT_ROOTS_START_BLOCK": "0",
        "INDEXER_OPTIMISM_L1_DEPOSITS_BATCH_SIZE": "500",
        "INDEXER_OPTIMISM_L2_WITHDRAWALS_START_BLOCK": "1",
        "INDEXER_OPTIMISM_L2_MESSAGE_PASSER_CONTRACT": config["optimism_l2_message_passer_contract"],
    }
    
    required_vars = [
        "portal_address",
        "l1_deposit_start_block", 
        "l1_withdrawals_start_block",
        "output_oracle_address"
    ]
    
    for var in required_vars:
        if var in optimism_args:
            key = var.upper()
            if var == "portal_address":
                key = "INDEXER_OPTIMISM_L1_PORTAL_CONTRACT"
            elif var == "l1_deposit_start_block":
                key = "INDEXER_OPTIMISM_L1_DEPOSITS_START_BLOCK"
            elif var == "l1_withdrawals_start_block":
                key = "INDEXER_OPTIMISM_L1_WITHDRAWALS_START_BLOCK"
            elif var == "output_oracle_address":
                key = "INDEXER_OPTIMISM_L1_OUTPUT_ORACLE_CONTRACT"
            
            env_vars[key] = optimism_args[var]
    
    if "extra_env_vars" in optimism_args:
        for key, value in optimism_args["extra_env_vars"].items():
            env_vars[key] = value
    
    backend_config = ServiceConfig(
        image=optimism_args.get("blockscout_optimism_image", config["blockscout_optimism_image"]),
        ports=used_ports,
        public_ports=public_ports,
        cmd=[
            "/bin/sh",
            "-c",
            'bin/blockscout eval "Elixir.Explorer.ReleaseTasks.create_and_migrate()" && bin/blockscout start',
        ],
        env_vars=env_vars,
        min_cpu=config["blockscout_min_cpu"],
        max_cpu=config["blockscout_max_cpu"],
        min_memory=config["blockscout_min_memory"],
        max_memory=config["blockscout_max_memory"],
        node_selectors=node_selectors,
    )
    
    blockscout_service = plan.add_service(service_name, backend_config)
    return blockscout_service

def _create_frontend_service(plan, config, blockscout_service, ethereum_args, node_selectors, port_publisher):
    service_name = config["service_name_blockscout_frontend"]
    
    frontend_used_ports = {
        config["http_port_id"]: utils.new_port_spec(
            config["http_port_number_frontend"],
            utils.TCP_PROTOCOL,
            utils.HTTP_APPLICATION_PROTOCOL,
        )
    }

    public_ports = frontend_used_ports
    
    rpc_url = ethereum_args.get("rpc_url", "http://localhost:8545")
    if hasattr(config, "api_host"):
        rpc_url = "https://" + config["api_host"].replace("blockscout-backend", "rpc")
    
    env_vars = {
        "NEXT_PUBLIC_API_HOST": config["api_host"] if hasattr(config, "api_host") else "{}:{}".format(
            blockscout_service.ip_address,
            blockscout_service.ports[config["http_port_id"]].number,
        ),
        "NEXT_PUBLIC_NETWORK_ID": config["network_id"],
        "NEXT_PUBLIC_APP_HOST": config["app_host"],
        "NEXT_PUBLIC_API_PROTOCOL": config["api_protocol"],
        "NEXT_PUBLIC_API_WEBSOCKET_PROTOCOL": config["ws_protocol"],
        "NEXT_PUBLIC_NETWORK_NAME": config["network_name"],
        "NEXT_PUBLIC_NETWORK_RPC_URL": rpc_url,
        "NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID": config["wallet_connect_id"],
        "NEXT_PUBLIC_AD_BANNER_PROVIDER": "none",
        "NEXT_PUBLIC_AD_TEXT_PROVIDER": "none",
        "NEXT_PUBLIC_IS_TESTNET": config["is_testnet"],
        "NEXT_PUBLIC_GAS_TRACKER_ENABLED": "true",
        "NEXT_PUBLIC_HAS_BEACON_CHAIN": config["has_beacon_chain"],
        "NEXT_PUBLIC_NETWORK_VERIFICATION_TYPE": "validation",
        "NEXT_PUBLIC_APP_PROTOCOL": config["api_protocol"],

        "NEXT_PUBLIC_APP_PORT": str(config["http_port_number_frontend"]),
        "NEXT_PUBLIC_USE_NEXT_JS_PROXY": "false" if hasattr(config, "api_host") else "true",
    }
    
    if "frontend_env_vars" in ethereum_args:
        for key, value in ethereum_args["frontend_env_vars"].items():
            env_vars[key] = value
    
    frontend_config = ServiceConfig(
        image=config["blockscout_frontend_image"],
        ports=frontend_used_ports,
        public_ports=public_ports,
        env_vars=env_vars,
        min_cpu=config["blockscout_min_cpu"],
        max_cpu=config["blockscout_max_cpu"],
        min_memory=config["blockscout_min_memory"],
        max_memory=config["blockscout_max_memory"],
        node_selectors=node_selectors,
    )
    
    frontend_service = plan.add_service(service_name, frontend_config)
    return frontend_service