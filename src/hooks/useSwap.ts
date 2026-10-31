import { useCallback, useEffect, useState } from 'react'
import { useAccount, usePublicClient, useWriteContract } from 'wagmi'
import { erc20Abi, parseEventLogs, type Address, type Hash } from 'viem'
import { toast } from 'sonner'
import { fxDeskAbi } from '@/contracts/fxDeskAbi'
import { describeError } from '@/lib/desk'
import { useDeskNetwork } from '@/lib/network'

export interface ActiveQuote {
  id: bigint
  user: Address
  amountIn: bigint
  rate: bigint
  estimatedOut: bigint
  fee: bigint
  minReceived: bigint
  /** Chain-time expiry in unix seconds. */
  expiry: number
  /** Seconds to add to the local clock to get chain time. */
  skew: number
  txHash: Hash
}

export type SwapPhase = 'idle' | 'approving' | 'quoting' | 'executing'

interface UseSwapArgs {
  usdc: Address | undefined
  onSettled: () => void
}

/** Quote-first swap flow: approve USDC, request a locked quote, execute it before expiry. */
export function useSwap({ usdc, onSettled }: UseSwapArgs) {
  const { address } = useAccount()
  const { network } = useDeskNetwork()
  const deskAddress = network.address
  const chainId = network.chainId
  const client = usePublicClient({ chainId })
  const { writeContractAsync } = useWriteContract()

  const [phase, setPhase] = useState<SwapPhase>('idle')
  const [quote, setQuote] = useState<ActiveQuote | undefined>()
  const [receiptHash, setReceiptHash] = useState<Hash | undefined>()
  const [now, setNow] = useState(() => Date.now() / 1000)

  useEffect(() => {
    if (!quote) return
    const timer = setInterval(() => setNow(Date.now() / 1000), 250)
    return () => clearInterval(timer)
  }, [quote])

  const secondsLeft = quote ? quote.expiry - (now + quote.skew) : 0
  const quoteValid = !!quote && secondsLeft > 0 && quote.user === address

  const clearQuote = useCallback(() => {
    setQuote(undefined)
    setReceiptHash(undefined)
  }, [])

  const fail = useCallback((error: unknown) => {
    const message = describeError(error)
    if (message) toast.error(message)
  }, [])

  const approve = useCallback(
    async (amount: bigint) => {
      if (!client || !usdc || !deskAddress) return false
      setPhase('approving')
      try {
        const hash = await writeContractAsync({
          chainId,
          address: usdc,
          abi: erc20Abi,
          functionName: 'approve',
          args: [deskAddress, amount],
        })
        await client.waitForTransactionReceipt({ hash })
        toast.success('USDC approved for the desk')
        return true
      } catch (error) {
        fail(error)
        return false
      } finally {
        setPhase('idle')
      }
    },
    [client, usdc, deskAddress, chainId, writeContractAsync, fail],
  )

  const requestQuote = useCallback(
    async (amountIn: bigint) => {
      if (!client || !deskAddress) return
      setPhase('quoting')
      setReceiptHash(undefined)
      try {
        const hash = await writeContractAsync({
          chainId,
          address: deskAddress,
          abi: fxDeskAbi,
          functionName: 'requestQuote',
          args: [amountIn],
        })
        const receipt = await client.waitForTransactionReceipt({ hash })
        if (receipt.status !== 'success') throw new Error('Transaction reverted')
        const [created] = parseEventLogs({ abi: fxDeskAbi, eventName: 'QuoteCreated', logs: receipt.logs })
        if (!created) throw new Error('Quote event missing from receipt')
        const block = await client.getBlock({ blockNumber: receipt.blockNumber })
        const localNow = Date.now() / 1000
        setNow(localNow)
        setQuote({
          id: created.args.quoteId,
          user: created.args.user,
          amountIn: created.args.amountIn,
          rate: created.args.rate,
          estimatedOut: created.args.estimatedOut,
          fee: created.args.fee,
          minReceived: created.args.minReceived,
          expiry: Number(created.args.expiry),
          skew: Number(block.timestamp) - localNow,
          txHash: hash,
        })
      } catch (error) {
        fail(error)
      } finally {
        setPhase('idle')
      }
    },
    [client, deskAddress, chainId, writeContractAsync, fail],
  )

  const execute = useCallback(async () => {
    if (!client || !deskAddress || !quote || !quoteValid) return
    setPhase('executing')
    try {
      const hash = await writeContractAsync({
        chainId,
        address: deskAddress,
        abi: fxDeskAbi,
        functionName: 'executeQuote',
        args: [quote.id, quote.minReceived],
      })
      const receipt = await client.waitForTransactionReceipt({ hash })
      if (receipt.status !== 'success') throw new Error('Transaction reverted')
      setReceiptHash(hash)
      setQuote(undefined)
      toast.success('Swap settled')
      onSettled()
    } catch (error) {
      fail(error)
    } finally {
      setPhase('idle')
    }
  }, [client, deskAddress, chainId, quote, quoteValid, writeContractAsync, fail, onSettled])

  return { phase, quote, quoteValid, secondsLeft, receiptHash, approve, requestQuote, execute, clearQuote }
}
