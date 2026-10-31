import { useState } from 'react'
import { useAccount, usePublicClient, useWriteContract } from 'wagmi'
import { erc20Abi, parseUnits, type Address, type Hash } from 'viem'
import { toast } from 'sonner'
import { Loader2, ShieldCheck } from 'lucide-react'
import { parseUsdc } from '@/onchain-money'
import { fxDeskAbi } from '@/contracts/fxDeskAbi'
import { RATE_DECIMALS, describeError } from '@/lib/desk'
import { useDeskNetwork } from '@/lib/network'
import { formatBps, formatRate, formatToken } from '@/lib/format'

interface Props {
  usdc: Address
  eurc: Address
  rate: bigint | undefined
  feeBps: number | undefined
  maxAmount: bigint | undefined
  paused: boolean | undefined
  onChanged: () => void
}

type Token = 'USDC' | 'EURC'

export function AdminPanel({ usdc, eurc, rate, feeBps, maxAmount, paused, onChanged }: Props) {
  const { address } = useAccount()
  const { network } = useDeskNetwork()
  const client = usePublicClient({ chainId: network.chainId })
  const { writeContractAsync } = useWriteContract()
  const [busy, setBusy] = useState<string | undefined>()
  const [rateInput, setRateInput] = useState('')
  const [feeInput, setFeeInput] = useState('')
  const [maxInput, setMaxInput] = useState('')
  const [invToken, setInvToken] = useState<Token>('EURC')
  const [invAmount, setInvAmount] = useState('')

  const run = async (label: string, steps: () => Promise<void>) => {
    if (!client) return
    setBusy(label)
    try {
      await steps()
      toast.success(`${label} confirmed`)
      onChanged()
    } catch (error) {
      const message = describeError(error)
      if (message) toast.error(message)
    } finally {
      setBusy(undefined)
    }
  }

  const exec = async (send: () => Promise<Hash>) => {
    if (!client) return
    const hash = await send()
    await client.waitForTransactionReceipt({ hash })
  }

  const inventory = async (mode: 'deposit' | 'withdraw') => {
    if (!client || !deskAddress || !address) return
    const token = invToken === 'USDC' ? usdc : eurc
    const amount = parseUsdc(invAmount)
    if (mode === 'deposit') {
      const approval = await writeContractAsync({
        chainId,
        address: token,
        abi: erc20Abi,
        functionName: 'approve',
        args: [deskAddress, amount],
      })
      await client.waitForTransactionReceipt({ hash: approval })
    }
    const hash = await writeContractAsync(
      mode === 'deposit'
        ? { ...base, functionName: 'depositInventory', args: [token, amount] }
        : { ...base, functionName: 'withdrawInventory', args: [token, amount, address] },
    )
    await client.waitForTransactionReceipt({ hash })
  }

  const deskAddress = network.address
  if (!deskAddress) return null
  const chainId = network.chainId
  const base = { chainId, address: deskAddress, abi: fxDeskAbi } as const

  const invValid = /^\d*\.?\d+$/.test(invAmount) && Number(invAmount) > 0
  const isBusy = busy !== undefined

  return (
    <section className="panel p-5 sm:p-6">
      <div className="mb-4 flex items-center gap-2">
        <ShieldCheck className="size-5" style={{ color: 'var(--accent)' }} />
        <h2 className="display text-xl font-semibold">Desk admin</h2>
        <span className="ml-auto text-xs" style={{ color: 'var(--subtle)' }}>
          Owner only
        </span>
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        <label className="grid gap-1.5 text-xs">
          <span className="label">Rate, EURC per USDC (now {formatRate(rate)})</span>
          <div className="flex gap-2">
            <input className="field" inputMode="decimal" placeholder="0.8600" value={rateInput} onChange={(e) => setRateInput(e.target.value)} />
            <button
              className="btn-ghost px-3 text-xs"
              disabled={isBusy || !/^\d*\.?\d+$/.test(rateInput)}
              onClick={() => void run('Rate update', () => exec(() => writeContractAsync({ ...base, functionName: 'setRate', args: [parseUnits(rateInput, RATE_DECIMALS)] })))}
            >
              Set
            </button>
          </div>
        </label>
        <label className="grid gap-1.5 text-xs">
          <span className="label">Fee, bps (now {feeBps ?? '--'} = {formatBps(feeBps)})</span>
          <div className="flex gap-2">
            <input className="field" inputMode="numeric" placeholder="30" value={feeInput} onChange={(e) => setFeeInput(e.target.value.replace(/\D/g, ''))} />
            <button
              className="btn-ghost px-3 text-xs"
              disabled={isBusy || feeInput === '' || Number(feeInput) > 1000}
              onClick={() => void run('Fee update', () => exec(() => writeContractAsync({ ...base, functionName: 'setFeeBps', args: [Number(feeInput)] })))}
            >
              Set
            </button>
          </div>
        </label>
        <label className="grid gap-1.5 text-xs">
          <span className="label">Max per swap, USDC (now {formatToken(maxAmount)})</span>
          <div className="flex gap-2">
            <input className="field" inputMode="decimal" placeholder="5" value={maxInput} onChange={(e) => setMaxInput(e.target.value)} />
            <button
              className="btn-ghost px-3 text-xs"
              disabled={isBusy || !/^\d*\.?\d+$/.test(maxInput) || Number(maxInput) <= 0}
              onClick={() => void run('Limit update', () => exec(() => writeContractAsync({ ...base, functionName: 'setMaxAmountPerSwap', args: [parseUsdc(maxInput)] })))}
            >
              Set
            </button>
          </div>
        </label>
      </div>

      <div className="inner mt-4 grid gap-3 p-4 sm:grid-cols-[auto_1fr_auto_auto] sm:items-end">
        <label className="grid gap-1.5 text-xs">
          <span className="label">Inventory token</span>
          <select className="field" value={invToken} onChange={(e) => setInvToken(e.target.value as Token)}>
            <option value="EURC">EURC</option>
            <option value="USDC">USDC</option>
          </select>
        </label>
        <label className="grid gap-1.5 text-xs">
          <span className="label">Amount</span>
          <input className="field" inputMode="decimal" placeholder="100" value={invAmount} onChange={(e) => setInvAmount(e.target.value)} />
        </label>
        <button className="btn-primary px-5 text-sm" disabled={isBusy || !invValid} onClick={() => void run('Deposit', () => inventory('deposit'))}>
          Deposit
        </button>
        <button className="btn-ghost px-5 text-sm" disabled={isBusy || !invValid} onClick={() => void run('Withdrawal', () => inventory('withdraw'))}>
          Withdraw
        </button>
      </div>

      <div className="mt-4 flex items-center justify-between gap-3">
        <span className="text-sm" style={{ color: 'var(--muted)' }}>
          Desk is{' '}
          <strong style={{ color: paused ? 'var(--danger)' : 'var(--success)' }}>{paused ? 'paused' : 'live'}</strong>
        </span>
        <button
          className="btn-ghost px-5 text-sm"
          disabled={isBusy}
          onClick={() => void run(paused ? 'Unpause' : 'Pause', () => exec(() => writeContractAsync({ ...base, functionName: paused ? 'unpause' : 'pause' })))}
        >
          {busy ? (
            <span className="flex items-center gap-2">
              <Loader2 className="size-4 animate-spin" /> {busy}...
            </span>
          ) : paused ? (
            'Unpause desk'
          ) : (
            'Pause desk'
          )}
        </button>
      </div>
    </section>
  )
}
