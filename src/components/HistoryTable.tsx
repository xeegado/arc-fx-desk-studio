import { ExternalLink } from 'lucide-react'
import { buildTxExplorerUrl } from '@/onchain-facts'
import { useDeskNetwork } from '@/lib/network'
import { formatRate, formatTimestamp, formatToken, shortHash } from '@/lib/format'
import type { HistoryRow, HistoryStatus } from '@/hooks/useHistory'

interface Props {
  connected: boolean
  rows: HistoryRow[] | undefined
  loading: boolean
  failed: boolean
}

const STATUS: Record<HistoryStatus, { label: string; color: string }> = {
  settled: { label: 'Settled', color: 'var(--success)' },
  expired: { label: 'Expired', color: 'var(--subtle)' },
  open: { label: 'Open', color: 'var(--warn)' },
}

export function HistoryTable({ connected, rows, loading, failed }: Props) {
  const { network } = useDeskNetwork()
  let empty: string | undefined
  if (!connected) empty = 'Connect a wallet to see your settlement history.'
  else if (failed) empty = 'History could not be loaded. It will retry shortly.'
  else if (loading) empty = 'Loading history...'
  else if (!rows || rows.length === 0) empty = 'No quotes or settlements yet. Your first swap will appear here.'

  return (
    <section className="panel p-5 sm:p-6">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="display text-xl font-semibold">Settlement history</h2>
        <span className="text-xs" style={{ color: 'var(--subtle)' }}>
          Your quotes on this desk
        </span>
      </div>

      {empty ? (
        <p className="inner p-6 text-center text-sm" style={{ color: 'var(--subtle)' }}>
          {empty}
        </p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-left text-sm">
            <thead>
              <tr className="label">
                {['Time', 'Pair', 'Paid', 'Received', 'Rate', 'Status', 'Transaction'].map((head) => (
                  <th key={head} className="whitespace-nowrap px-3 py-2 font-semibold">
                    {head}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows?.map((row) => {
                const status = STATUS[row.status]
                return (
                  <tr key={row.quoteId.toString()} style={{ borderTop: '1px solid var(--border)' }}>
                    <td className="whitespace-nowrap px-3 py-3" style={{ color: 'var(--muted)' }}>
                      {formatTimestamp(row.time)}
                    </td>
                    <td className="whitespace-nowrap px-3 py-3 font-medium">USDC / EURC</td>
                    <td className="whitespace-nowrap px-3 py-3 tabular-nums">{formatToken(row.paid, 2)} USDC</td>
                    <td className="whitespace-nowrap px-3 py-3 tabular-nums">
                      {row.received === undefined ? '--' : `${formatToken(row.received, 4)} EURC`}
                    </td>
                    <td className="whitespace-nowrap px-3 py-3 tabular-nums">{formatRate(row.rate)}</td>
                    <td className="whitespace-nowrap px-3 py-3 font-semibold" style={{ color: status.color }}>
                      {status.label}
                    </td>
                    <td className="whitespace-nowrap px-3 py-3">
                      <a
                        href={buildTxExplorerUrl(network.chainId, row.txHash)}
                        target="_blank"
                        rel="noreferrer"
                        className="mono inline-flex items-center gap-1 text-xs"
                        style={{ color: 'var(--accent)' }}
                      >
                        {shortHash(row.txHash)} <ExternalLink className="size-3" />
                      </a>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  )
}
