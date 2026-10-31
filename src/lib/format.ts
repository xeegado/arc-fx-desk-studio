import { formatUnits } from 'viem'
import { formatUnitsFixed } from '@/onchain-money'
import { RATE_DECIMALS, TOKEN_DECIMALS } from '@/lib/desk'

/** Format a 6-decimal token amount with thousands separators and a fixed number of digits. */
export function formatToken(raw: bigint | undefined, digits = 2): string {
  if (raw === undefined) return '--'
  const fixed = formatUnitsFixed(raw, TOKEN_DECIMALS, digits)
  const [whole, frac] = fixed.split('.')
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  return frac === undefined ? grouped : `${grouped}.${frac}`
}

/** Format the desk rate (EURC per 1 USDC). */
export function formatRate(raw: bigint | undefined): string {
  if (raw === undefined) return '--'
  const value = Number(formatUnits(raw, RATE_DECIMALS))
  return value.toFixed(4)
}

export function formatBps(bps: number | bigint | undefined): string {
  if (bps === undefined) return '--'
  return `${(Number(bps) / 100).toFixed(2)}%`
}

export function shortHash(hash: string): string {
  return `${hash.slice(0, 8)}...${hash.slice(-6)}`
}

export function shortAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

export function formatClock(totalSeconds: number): string {
  const s = Math.max(0, Math.ceil(totalSeconds))
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}

export function formatTimestamp(seconds: number): string {
  return new Date(seconds * 1000).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
}
