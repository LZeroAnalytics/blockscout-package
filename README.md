# Blockscout Package (plug‑and‑play explorer)

A ready‑to‑import **Blockscout + Postgres** bundle for [Kurtosis](https://docs.kurtosis.com) environments.

* Drop it into **any EVM dev‑net** and get a full explorer UI in seconds.
* Or run it solo if you just need a local explorer.

---

## 📦 How to import

```python
blockscout = import_module(
    "github.com/LZeroAnalytics/blockscout-package",
    params = {
        "rpc_url":  chain.rpc_url,      # JSON‑RPC of your chain
        "ws_url":   chain.ws_url,       # WebSocket endpoint
        "chain_id": chain.chain_id,     # shown in the UI
        "ui_port":  4000,               # host port (optional)
    }
)
````

Blockscout will be reachable at `http://localhost:<ui_port>`.

---

## ⚙️ Parameters

| Name        | Type | Default | Purpose                                |
| ----------- | ---- | ------- | -------------------------------------- |
| `rpc_url`   | str  | —       | **Required** – JSON‑RPC to index       |
| `ws_url`    | str  | —       | WebSocket endpoint (needed by indexer) |
| `chain_id`  | int  | `1`     | EVM chain ID shown in UI               |
| `ui_port`   | int  | `4000`  | Host port for Blockscout front‑end     |
| `db_volume` | str  | `""`    | Named Docker volume for Postgres       |

---

## 🛑 Cleaning up

```bash
kurtosis enclave rm <your‑enclave>   # remove service + data
```

---

## 📝 License

MIT – see the [LICENSE](./LICENSE) file.
