import { useQuery } from '@tanstack/react-query'
import { useAccount, usePublicClient } from 'wagmi'
import type { Hash } from 'viem'
import { fxDeskAbi } from '@/contracts/fxDeskAbi'
import { QUOTE_TTL_SECONDS } from '@/lib/desk'
import { useDeskNetwork } from '@/lib/network'

export type HistoryStatus = 'settled' | 'expired' | 'open'

export interface HistoryRow {
  quoteId: bigint
  time: number
  paid: bigint
  received?: bigint
  rate: bigint
  status: HistoryStatus
  txHash: Hash
}

/** Used only when the deployment block is not configured: scan a short recent window. */
const FALLBACK_LOOKBACK = 5_000n
const START_CHUNK = 10_000n
const MIN_CHUNK = 250n

/** Walk [from, to] in bounded ranges, halving the range if the RPC rejects a request. */
async function scanRange<T>(
  from: bigint,
  to: bigint,
  fetchChunk: (fromBlock: bigint, toBlock: bigint) => Promise<T[]>,
): Promise<T[]> {
  const out: T[] = []
  let size = START_CHUNK
  let start = from
  while (start <= to) {
    const end = start + size - 1n > to ? to : start + size - 1n
    try {
      out.push(...(await fetchChunk(start, end)))
      start = end + 1n
    } catch (error) {
      if (size <= MIN_CHUNK) throw error
      size = size / 2n
    }
  }
  return out
}

/** Settlement history for the connected wallet, assembled from QuoteCreated and SettlementRecorded events. */
export function useHistory() {
  const { address } = useAccount()
  const { network } = useDeskNetwork()
  const deskAddress = network.address
  const client = usePublicClient({ chainId: network.chainId })

  return useQuery({
    queryKey: ['fx-history', network.chainId, deskAddress, address],
    enabled: !!client && !!address && !!deskAddress,
    refetchInterval: 15_000,
    queryFn: async (): Promise<HistoryRow[]> => {
      if (!client || !address || !deskAddress) return []
      const head = await client.getBlockNumber()
      const fallback = head > FALLBACK_LOOKBACK ? head - FALLBACK_LOOKBACK : 0n
      const from = network.fromBlock ?? fallback
      const args = { user: address }

      const [created, settled] = await Promise.all([
        scanRange(from, head, (fromBlock, toBlock) =>
          client.getContractEvents({
            address: deskAddress,
            abi: fxDeskAbi,
            eventName: 'QuoteCreated',
            args,
            fromBlock,
            toBlock,
          }),
        ),
        scanRange(from, head, (fromBlock, toBlock) =>
          client.getContractEvents({
            address: deskAddress,
            abi: fxDeskAbi,
            eventName: 'SettlementRecorded',
            args,
            fromBlock,
            toBlock,
          }),
        ),
      ])

      const settledById = new Map(settled.map((log) => [log.args.quoteId, log]))
      const nowSec = Math.floor(Date.now() / 1000)

      const rows: HistoryRow[] = []
      for (const log of created) {
        const { quoteId, amountIn, rate, expiry, minReceived } = log.args
        if (quoteId === undefined || amountIn === undefined || rate === undefined || expiry === undefined) continue
        const settlement = settledById.get(quoteId)
        if (settlement) {
          rows.push({
            quoteId,
            time: Number(settlement.args.timestamp ?? 0n),
            paid: amountIn,
            received: settlement.args.amountOut,
            rate,
            status: 'settled',
            txHash: settlement.transactionHash,
          })
        } else {
          rows.push({
            quoteId,
            time: Number(expiry) - QUOTE_TTL_SECONDS,
            paid: amountIn,
            received: undefined,
            rate,
            status: nowSec > Number(expiry) ? 'expired' : 'open',
            txHash: log.transactionHash,
          })
        }
        void minReceived
      }
      return rows.sort((a, b) => b.time - a.time)
    },
  })
}
