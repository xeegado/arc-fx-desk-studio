# [App Name]

> Built with Arc Studio - money-powered apps in minutes

This is the **project memory** - what Arc Studio remembers about building this app. It helps future agents (or humans) understand and extend the project.

---

## What This App Does

[Brief description of what the app does and its primary use case]

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS
- Web3: wagmi v2, viem v2, ConnectKit
- Contracts: Solidity 0.8.28 + Foundry. Sources in `contracts/`, unit tests in `contracts/test/*.t.sol`. Build with `bun run contracts:build` (`forge build`), test with `bun run contracts:test` (`forge test`).
- Wallet: injected (MetaMask, etc.)
- Chain: Arc Testnet (Chain ID: 5042002, imported from `viem/chains`)
- Token: USDC (6 decimals) (Address: 0x3600000000000000000000000000000000000000, Chain: Arc Testnet)
- Toasts: Sonner

## Key Files

- `src/App.tsx` - Main application logic
- `src/components/` - UI components
- `src/config.ts` - wagmi config (chains, connectors, transports)

## Share links

- Starter apps already ship `getShareBase`, `buildShareLink` and `installShareSync` in `src/lib/share.ts`; import them instead of rewriting them.
- Keep shareable state in the URL path or query, not in the `#fragment`.
- Never put a secret (private key, claim secret, seed phrase, session token, API key) in the URL path or query, encoded or not: every in-app path and query is mirrored to the visitor's studio.arc.io address bar and browser history and reaches servers. A bearer claim secret goes only in the `#fragment` appended to the share link (`` `${await buildShareLink('/claim')}#${secret}` ``) and is read from `location.hash` on load. A link to the app's own share URL shown inside the app must be copy-only or open in a new tab with `target="_blank" rel="noopener noreferrer"`.
- Build every link a user copies or sends with `buildShareLink()` from `src/lib/share.ts`.
- Keep the `installShareSync()` call in `src/main.tsx` when editing it; it keeps the Studio address bar in step with in-app navigation.
- Navigate inside the app with relative links.

## To Run

```bash
bun install
bun run dev
```

## Arc FX Desk (deployed)

- Contract: `contracts/ArcFxDesk.sol` (USDC to EURC, owner-funded inventory, 60-second locked quotes).
- Arc Testnet: `0x64270910c84ca429410b326e8a41fab4ff8fc6f3`, deployed at block 69908069.
- Owner: `0xB2ec3393C02dAdA8b996789CaF14E559CDc616B9` (Ownable2Step, renounce disabled).
- Token addresses are constructor args. Testnet EURC `0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a`; mainnet EURC differs, check Circle's Arc contract-address docs before any mainnet deploy.
- Starting terms: rate 0.86 EURC per USDC (1e18 scale), fee 30 bps, max 5 USDC per swap.
- Frontend reads `VITE_FX_DESK_TESTNET_ADDRESS` and `VITE_FX_DESK_TESTNET_FROM_BLOCK` from `.env`. ABI lives in `src/contracts/fxDeskAbi.ts` (regenerate from the Foundry artifact after contract changes).
- Tests: `contracts/test/ArcFxDesk.*.t.sol` (92 passing).

## Arc Mainnet

- App supports both networks (`src/lib/desk.ts`, `src/lib/network.tsx`). Mainnet is active once `VITE_FX_DESK_MAINNET_ADDRESS` and `VITE_FX_DESK_MAINNET_FROM_BLOCK` are set in `.env` (restart the dev server).
- Mainnet EURC `0xbEf5f6d51CB62b58e6A8f77868681825C6fe21c1` (6 decimals, verified onchain). Token addresses are read from the desk contract, not hardcoded in the app.
- `deploy/ArcFxDesk.remix.sol` is the Remix-ready copy of the contract (OpenZeppelin 5.6.1 imports pinned). Mainnet deploy is done by the user from MetaMask; Arc Studio does not deploy to mainnet.

- Arc Mainnet desk: `0x4d3F0F5445Af1D88E27557029848d5E94a6c9C28`, deployed at block 28763004 by the owner from Remix. Owner `0xB2ec3393C02dAdA8b996789CaF14E559CDc616B9`; USDC/EURC verified onchain. Initial rate 0.8985 EURC per USDC, fee 30 bps, max 5 USDC.
