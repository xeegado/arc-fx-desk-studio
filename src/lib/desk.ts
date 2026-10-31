import { getAddress, isAddress, type Address } from 'viem'
import { arc, arcTestnet } from 'viem/chains'
import { getChain, USDC_DECIMALS } from '@/onchain-facts'

export type NetworkKind = 'testnet' | 'mainnet'

/** One Arc network the desk can run on, with its deployment (if any). */
export interface DeskNetwork {
  chainId: number
  kind: NetworkKind
  label: string
  /** Desk contract on this network, or undefined when not deployed yet. */
  address: Address | undefined
  /** Block the desk was deployed at, used as the start of the history scan. */
  fromBlock: bigint | undefined
}

function readAddress(value: unknown): Address | undefined {
  return typeof value === 'string' && isAddress(value) ? getAddress(value) : undefined
}

function readBlock(value: unknown): bigint | undefined {
  return typeof value === 'string' && /^\d+$/.test(value) ? BigInt(value) : undefined
}

export const TESTNET: DeskNetwork = {
  chainId: arcTestnet.id,
  kind: 'testnet',
  label: 'Arc Testnet',
  address: readAddress(import.meta.env.VITE_FX_DESK_TESTNET_ADDRESS),
  fromBlock: readBlock(import.meta.env.VITE_FX_DESK_TESTNET_FROM_BLOCK),
}

export const MAINNET: DeskNetwork = {
  chainId: arc.id,
  kind: 'mainnet',
  label: 'Arc Mainnet',
  address: readAddress(import.meta.env.VITE_FX_DESK_MAINNET_ADDRESS),
  fromBlock: readBlock(import.meta.env.VITE_FX_DESK_MAINNET_FROM_BLOCK),
}

export const DESK_NETWORKS: readonly DeskNetwork[] = [TESTNET, MAINNET]

export function getDeskNetwork(chainId: number | undefined): DeskNetwork | undefined {
  return DESK_NETWORKS.find((network) => network.chainId === chainId)
}

/** The desk quotes EURC per 1 USDC with this many decimals (RATE_SCALE = 1e18). */
export const RATE_DECIMALS = 18

/** Both desk tokens are validated onchain to use this many decimals. */
export const TOKEN_DECIMALS = USDC_DECIMALS

export const QUOTE_TTL_SECONDS = 60

/** Name for any wallet chain id, for the "wrong network" messaging. */
export function chainName(chainId: number | undefined): string {
  if (chainId === undefined) return 'no network'
  return getDeskNetwork(chainId)?.label ?? getChain(chainId)?.name ?? `chain ${chainId}`
}

/** Turn a wallet or RPC error into a short, actionable message. Returns null for user rejections. */
export function describeError(error: unknown): string | null {
  const message = (error instanceof Error ? error.message : String(error)).toLowerCase()
  if (message.includes('user rejected') || message.includes('user denied')) return null
  if (message.includes('quoteexpired')) return 'This quote expired. Request a new one.'
  if (message.includes('slippageexceeded')) return 'Payout is below your minimum. Request a new quote.'
  if (message.includes('insufficientinventory')) return 'The desk does not hold enough EURC right now.'
  if (message.includes('enforcedpause')) return 'The desk is paused.'
  if (message.includes('amountexceedsmaximum')) return 'Amount is above the per-swap limit.'
  if (message.includes('insufficient funds') || message.includes('exceeds balance')) {
    return 'Insufficient balance for this transaction.'
  }
  if (message.includes('reverted')) return 'Transaction reverted. Request a fresh quote and try again.'
  if (message.includes('network') || message.includes('timeout')) return 'Network issue. Check your connection and retry.'
  return 'Something went wrong. Please try again.'
}
