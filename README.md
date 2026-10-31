# Arc FX Desk

A small quote-first stablecoin FX desk on Arc. Connect a wallet, request a locked 60-second quote to swap USDC for EURC, and execute it before it expires. The desk owner funds inventory and sets the rate, fee and per-swap limit.

Built with [Arc Studio](https://studio.arc.io)

## Tech stack

- React, Vite, TypeScript, Tailwind CSS
- wagmi, viem, ConnectKit
- Solidity 0.8.28 with Foundry and OpenZeppelin

## Development

Prerequisites: [Bun](https://bun.sh) and [Foundry](https://book.getfoundry.sh).

```bash
bun install
bun run dev          # start the app
bun run contracts:build
bun run contracts:test
bun run check        # lint and typecheck
```

### Environment variables

- `VITE_FX_DESK_TESTNET_ADDRESS`: address of the deployed desk contract on Arc Testnet.
- `VITE_FX_DESK_TESTNET_FROM_BLOCK`: block the desk was deployed at, used to load settlement history.
- `VITE_FX_DESK_MAINNET_ADDRESS`: address of the desk contract on Arc Mainnet (leave unset until you have deployed it).
- `VITE_FX_DESK_MAINNET_FROM_BLOCK`: block the mainnet desk was deployed at.
- `RPC_PROXY_BASE_URL`, `RPC_PROXY_TOKEN`, `RPC_PROXY_CHAINS`: provisioned by Arc Studio, optional outside Arc Studio.

## Features

- Wallet connection with an Arc Testnet / Arc Mainnet network switch and label
- USDC and EURC balances, plus desk inventory
- Quote-first swap with rate, fee, minimum received and a live countdown
- Settlement history with links to the Arc explorer
- Owner-only admin panel: rate, fee, limit, pause, and inventory deposit or withdrawal
