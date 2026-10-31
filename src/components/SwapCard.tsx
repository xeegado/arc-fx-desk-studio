import { useMemo, useState } from 'react'
import { useAccount } from 'wagmi'
import { ConnectKitButton } from 'connectkit'
import { TokenEURC, TokenUSDC } from '@web3icons/react'
import { ExternalLink, Loader2, Timer } from 'lucide-react'
import { formatUsdc, parseUsdc } from '@/onchain-money'
import { buildTxExplorerUrl } from '@/onchain-facts'
import { QUOTE_TTL_SECONDS } from '@/lib/desk'
import { useDeskNetwork } from '@/lib/network'
import { formatBps, formatClock, formatRate, formatToken, shortHash } from '@/lib/format'
import { useSwap } from '@/hooks/useSwap'
import type { Address } from 'viem'

interface Props {
  usdc: Address | undefined
  rate: bigint | undefined
  feeBps: number | undefined
  maxAmount: bigint | undefined
  paused: boolean | undefined
  usdcBalance: bigint | undefined
  allowance: bigint | undefined
  deskEurc: bigint | undefined
  onSettled: () => void
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between py-1.5 text-sm">
      <span style={{ color: 'var(--subtle)' }}>{label}</span>
      <span className="tabular-nums font-medium">{value}</span>
    </div>
  )
}

function parseAmountInput(value: string): bigint | undefined {
  if (!value) return undefined
  try {
    const parsed = parseUsdc(value)
    return parsed > 0n ? parsed : undefined
  } catch {
    return undefined
  }
}

export function SwapCard(props: Props) {
  const { usdc, rate, feeBps, maxAmount, paused, usdcBalance, allowance, deskEurc, onSettled } = props
  const { isConnected } = useAccount()
  const { network, walletOnUnsupportedChain, switching, select } = useDeskNetwork()
  const swap = useSwap({ usdc, onSettled })
  const [amount, setAmount] = useState('')

  const amountRaw = parseAmountInput(amount)
  const wrongChain = isConnected && walletOnUnsupportedChain
  const busy = swap.phase !== 'idle'

  const problem = useMemo(() => {
    if (amount && amountRaw === undefined) return 'Enter a valid USDC amount (up to 6 decimals).'
    if (amountRaw === undefined) return undefined
    if (maxAmount !== undefined && amountRaw > maxAmount) return `Above the ${formatToken(maxAmount)} USDC per-swap limit.`
    if (usdcBalance !== undefined && amountRaw > usdcBalance) return 'Amount exceeds your USDC balance.'
    if (rate !== undefined && deskEurc !== undefined) {
      const estimate = (amountRaw * rate) / 10n ** 18n
      if (estimate > deskEurc) return 'The desk does not hold enough EURC for this size.'
    }
    return undefined
  }, [amount, amountRaw, maxAmount, usdcBalance, rate, deskEurc])

  const needsApproval = amountRaw !== undefined && allowance !== undefined && allowance < amountRaw
  const canAct = amountRaw !== undefined && !problem && !paused && !busy

  const setMax = () => {
    if (usdcBalance === undefined || maxAmount === undefined) return
    const cap = usdcBalance < maxAmount ? usdcBalance : maxAmount
    swap.clearQuote()
    setAmount(formatUsdc(cap))
  }

  const onPrimary = async () => {
    if (amountRaw === undefined) return
    if (needsApproval) {
      await swap.approve(amountRaw)
      return
    }
    await swap.requestQuote(amountRaw)
  }

  const quote = swap.quote
  const left = Math.max(0, swap.secondsLeft)
  const expired = !!quote && !swap.quoteValid

  let primaryLabel = 'Request quote'
  if (swap.phase === 'approving') primaryLabel = 'Approving USDC...'
  else if (swap.phase === 'quoting') primaryLabel = 'Requesting quote...'
  else if (needsApproval) primaryLabel = 'Approve USDC'
  else if (quote) primaryLabel = 'Request new quote'

  return (
    <section className="panel p-5 sm:p-6">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="display text-xl font-semibold">Swap</h2>
        <span className="text-xs" style={{ color: 'var(--subtle)' }}>
          Quote valid for {QUOTE_TTL_SECONDS}s
        </span>
      </div>

      <div className="inner p-4">
        <div className="flex items-center justify-between">
          <span className="label">You pay</span>
          <button
            className="text-xs font-semibold disabled:opacity-40"
            style={{ color: 'var(--accent)' }}
            disabled={usdcBalance === undefined || maxAmount === undefined}
            onClick={setMax}
          >
            {usdcBalance === undefined ? 'Balance unavailable' : `Balance ${formatToken(usdcBalance)} · Max`}
          </button>
        </div>
        <div className="mt-2 flex items-center gap-3">
          <input
            inputMode="decimal"
            value={amount}
            placeholder="0.00"
            aria-label="USDC amount"
            onChange={(event) => {
              const next = event.target.value.replace(/[^0-9.]/g, '')
              if (next === '' || /^\d*\.?\d*$/.test(next)) {
                setAmount(next)
                swap.clearQuote()
              }
            }}
            className="display w-full min-w-0 bg-transparent text-4xl font-bold tabular-nums outline-none placeholder:opacity-30"
          />
          <span className="flex shrink-0 items-center gap-2 rounded-full px-3 py-1.5 text-sm font-semibold" style={{ background: 'var(--surface-strong)' }}>
            <TokenUSDC variant="branded" size={20} /> USDC
          </span>
        </div>
      </div>

      <div className="inner mt-3 p-4">
        <span className="label">You receive at least</span>
        <div className="mt-2 flex items-center gap-3">
          <div className="display w-full min-w-0 text-4xl font-bold tabular-nums" style={{ color: quote ? 'var(--ink)' : 'var(--subtle)' }}>
            {quote ? formatToken(quote.minReceived, 4) : '--'}
          </div>
          <span className="flex shrink-0 items-center gap-2 rounded-full px-3 py-1.5 text-sm font-semibold" style={{ background: 'var(--surface-strong)' }}>
            <TokenEURC variant="branded" size={20} /> EURC
          </span>
        </div>
      </div>

      <div className="mt-4 rounded-xl px-4 py-2" style={{ background: 'rgba(255,255,255,0.03)' }}>
        {quote ? (
          <>
            <Row label="Rate (locked)" value={`1 USDC = ${formatRate(quote.rate)} EURC`} />
            <Row label="Fee" value={`${formatToken(quote.fee, 4)} EURC`} />
            <Row label="Minimum received" value={`${formatToken(quote.minReceived, 4)} EURC`} />
            <div className="mt-2 pb-2">
              <div className="mb-1.5 flex items-center justify-between text-xs">
                <span className="flex items-center gap-1.5" style={{ color: expired ? 'var(--danger)' : 'var(--subtle)' }}>
                  <Timer className="size-3.5" />
                  {expired ? 'Quote expired' : 'Expires in'}
                </span>
                <span className="mono tabular-nums" style={{ color: expired ? 'var(--danger)' : 'var(--ink)' }}>
                  {formatClock(left)}
                </span>
              </div>
              <div className="h-1.5 overflow-hidden rounded-full" style={{ background: 'var(--surface-strong)' }}>
                <div
                  className="h-full origin-left rounded-full"
                  style={{
                    background: left <= 10 ? 'var(--danger)' : 'var(--accent)',
                    transform: `scaleX(${Math.min(1, left / QUOTE_TTL_SECONDS)})`,
                    transition: 'transform 0.25s linear',
                  }}
                />
              </div>
            </div>
          </>
        ) : (
          <>
            <Row label="Desk rate (indicative)" value={rate === undefined ? '--' : `1 USDC = ${formatRate(rate)} EURC`} />
            <Row label="Desk fee" value={formatBps(feeBps)} />
            <p className="pb-1.5 pt-1 text-xs" style={{ color: 'var(--subtle)' }}>
              Request a quote to lock the rate, fee and minimum received for {QUOTE_TTL_SECONDS} seconds.
            </p>
          </>
        )}
      </div>

      {(problem || paused) && (
        <p className="mt-3 text-sm" style={{ color: 'var(--danger)' }} role="alert">
          {paused ? 'The desk is paused. Quotes and swaps are unavailable.' : problem}
        </p>
      )}

      <div className="mt-4 grid gap-2.5">
        {!isConnected ? (
          <ConnectKitButton.Custom>
            {({ show }) => (
              <button className="btn-primary w-full text-sm" onClick={show}>
                Connect wallet
              </button>
            )}
          </ConnectKitButton.Custom>
        ) : wrongChain ? (
          <button className="btn-primary w-full text-sm" disabled={switching} onClick={() => select(network.chainId)}>
            Switch to {network.label}
          </button>
        ) : (
          <>
            <button
              className={quote && swap.quoteValid ? 'btn-ghost w-full text-sm' : 'btn-primary w-full text-sm'}
              disabled={!canAct}
              onClick={() => void onPrimary()}
            >
              {busy && swap.phase !== 'executing' ? (
                <span className="flex items-center justify-center gap-2">
                  <Loader2 className="size-4 animate-spin" /> {primaryLabel}
                </span>
              ) : (
                primaryLabel
              )}
            </button>
            <button
              className={quote && swap.quoteValid ? 'btn-primary w-full text-sm' : 'btn-ghost w-full text-sm'}
              disabled={!swap.quoteValid || busy}
              onClick={() => void swap.execute()}
            >
              {swap.phase === 'executing' ? (
                <span className="flex items-center justify-center gap-2">
                  <Loader2 className="size-4 animate-spin" /> Settling...
                </span>
              ) : (
                'Execute swap'
              )}
            </button>
          </>
        )}
      </div>

      {swap.receiptHash && (
        <div className="inner mt-4 flex items-center justify-between gap-3 p-3 text-sm">
          <span style={{ color: 'var(--success)' }} className="font-semibold">
            Settled
          </span>
          <a
            href={buildTxExplorerUrl(network.chainId, swap.receiptHash)}
            target="_blank"
            rel="noreferrer"
            className="mono inline-flex items-center gap-1 text-xs"
            style={{ color: 'var(--accent)' }}
          >
            {shortHash(swap.receiptHash)} <ExternalLink className="size-3" />
          </a>
        </div>
      )}
    </section>
  )
}
