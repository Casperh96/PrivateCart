# Private Cart — Encrypted Shopping Cart on Zama FHEVM

Aggregated totals without revealing individual items. Users add **encrypted prices** and a **category** to a cart; the smart contract stores **only encrypted aggregates** (sum per cart and per category bucket). Individual items are never stored or emitted.


## ✨ What this project demonstrates

* **FHE on-chain**: all arithmetic (sum, category counters) runs on encrypted values using Zama FHEVM.
* **Privacy by design**: only *final totals* and *category aggregates* are kept; no item list exists on-chain.
* **Optional public transparency**: the owner can flip aggregates to be publicly decryptable for dashboards.
* **User private reads**: when not public, users can request per-handle decryption via `userDecrypt` (Relayer SDK, EIP‑712).

---

## 🧱 Architecture

* **Solidity (FHE)** — `PrivateCart` contract using `@fhevm/solidity` primitives (`FHE`, `euint64`, `ebool`, etc.).

  * `initCart(cartId, owner)` — creates/clears a cart and binds an owner.
  * `addItem(cartId, priceExt, category, proof)` — folds encrypted `price` (uint64 cents) into totals; increments a category counter. No item details are stored.
  * `makeCartPublic(cartId)` — toggles aggregates to publicly decryptable.
  * `getAggregateHandles(cartId)` — returns `bytes32` handles for: total and each category bucket.
  * `ownerOf(cartId)` — plain owner address, used by the UI to show admin tools.

* **Frontend (Vanilla HTML/JS)** — single file at `frontend/public/index.html` (no bundler):

  * **ethers v6** for wallet & txs.
  * **Relayer SDK v0.2.0** to encrypt inputs (`createEncryptedInput.add64`) and to perform `publicDecrypt` / `userDecrypt`.
  * Minimal, dark UI with sections for **Submit encrypted item**, **Cart admin tools**, **Read aggregates**.

---

## 🗂️ Folders

```
frontend/
  public/
    index.html        # SPA UI
contracts/
  PrivateCart.sol     # FHEVM contract (example)
```

---

## 🔑 Smart‑contract API (summary)

```solidity
// init or reset aggregates and set owner
function initCart(bytes32 cartId, address owner) external;

// add one encrypted item (price = uint64 cents), category in [0..7]
function addItem(bytes32 cartId, externalEuint64 priceExt, uint8 category, bytes calldata proof) external;

// make per-cart aggregates publicly decryptable
function makeCartPublic(bytes32 cartId) external;

// read encrypted handles for total and category buckets
function getAggregateHandles(bytes32 cartId)
  external view returns (bytes32 totalH, bytes32[8] memory categoryHs);

function ownerOf(bytes32 cartId) external view returns (address);
```

> Buckets are an example (e.g. **Food, Electronics, Books, Fashion, Home, Beauty, Sports, Other**). You can change the mapping in the UI only; the contract stores indexes 0..7.

---

## ⚙️ Configuration

Open `frontend/public/index.html` and set the config at the top of the script:

```js
window.CONFIG = {
  NETWORK_NAME: "Sepolia",
  CHAIN_ID_HEX: "0xaa36a7",                // 11155111
  CONTRACT_ADDRESS: "0xYourPrivateCart...", // deployed PrivateCart
  RELAYER_URL: "https://relayer.testnet.zama.cloud"
};
```

---

## 🚀 Quick start

### 1) Install deps for contracts (optional)

```bash
pnpm i     # or npm i / yarn
```

### 2) Deploy the contract (example with Foundry/Hardhat)

```bash
# Foundry
forge create --rpc-url $SEPOLIA_RPC --private-key $PK \
  src/PrivateCart.sol:PrivateCart
# copy the deployed address into CONFIG.CONTRACT_ADDRESS
```

### 3) Serve the frontend

Any static server works. Examples:

```bash
# Using serve
npx serve frontend/public -p 5173
# Or simple python
python3 -m http.server --directory frontend/public 5173
```

Open [http://localhost:5173](http://localhost:5173) and **Connect Wallet**.

---

## 🧪 How to use

1. **Admin:** choose a *cart key* (arbitrary text) → UI hashes it to `bytes32 cartId`.
2. Click **Init/Reset Cart**. This sets you as the cart owner.
3. **User:** add items via **Submit encrypted item**:

   * Enter the same *cart key*.
   * Price in cents (e.g., 12.34 USD → `1234`).
   * Category bucket (Food / Electronics / …).
   * Click **Add Encrypted Item**.
4. **Read aggregates**:

   * If owner made aggregates public → click **Read (publicDecrypt → userDecrypt)** to show totals.
   * If not public → UI requests an EIP‑712 signature and calls Relayer `userDecrypt` for your address.

> The contract never stores item lines — only encrypted aggregates per cart.

---

## 📄 License

MIT — see `LICENSE`.


