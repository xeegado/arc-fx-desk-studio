import type { ReactNode } from 'react'
import { TokenEURC, TokenUSDC } from '@web3icons/react'
import { formatToken } from '@/lib/format'

interface Props {
  connected: boolean
  usdcBalance: bigint | undefined
  eurcBalance: bigint | undefined
  deskUsdc: bigint | undefined
  deskEurc: bigint | undefined
}

function Tile({ icon, symbol, value, hint }: { icon: ReactNode; symbol: string; value: string; hint: string }) {
  return (
    <div className="inner p-4">
      <div className="mb-3 flex items-center gap-2">
        {icon}
        <span className="label">{symbol}</span>
      </div>
      <div className="display text-3xl font-bold tabular-nums">{value}</div>
      <p className="mt-1 text-xs" style={{ color: 'var(--subtle)' }}>
        {hint}
      </p>
    </div>
  )
}

export function BalanceCards({ connected, usdcBalance, eurcBalance, deskUsdc, deskEurc }: Props) {
  const mine = (value: bigint | undefined) => (connected ? formatToken(value) : '--')
  return (
    <section className="panel p-5">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="label">Your balances</h2>
        <span className="text-xs" style={{ color: 'var(--subtle)' }}>
          ERC-20 view, 6 decimals
        </span>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <Tile
          icon={<TokenUSDC variant="branded" size={22} />}
          symbol="USDC"
          value={mine(usdcBalance)}
          hint={connected ? 'In your wallet' : 'Connect to view'}
        />
        <Tile
          icon={<TokenEURC variant="branded" size={22} />}
          symbol="EURC"
          value={mine(eurcBalance)}
          hint={connected ? 'In your wallet' : 'Connect to view'}
        />
      </div>

      <div className="mt-4 flex flex-wrap items-center justify-between gap-2 rounded-xl px-4 py-3 text-xs" style={{ background: 'rgba(255,255,255,0.03)' }}>
        <span className="label">Desk inventory</span>
        <span className="tabular-nums" style={{ color: 'var(--ink-2)' }}>
          {formatToken(deskEurc)} EURC
          <span style={{ color: 'var(--subtle)' }}> / </span>
          {formatToken(deskUsdc)} USDC
        </span>
      </div>
    </section>
  )
}
