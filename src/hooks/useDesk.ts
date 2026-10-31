import { useAccount, useReadContracts } from 'wagmi'
import { erc20Abi, type Address } from 'viem'
import { fxDeskAbi } from '@/contracts/fxDeskAbi'
import { useDeskNetwork } from '@/lib/network'

const POLL_MS = 8_000

/** Public desk configuration, read live from the contract. */
export function useDeskState() {
  const { network } = useDeskNetwork()
  const desk = { address: network.address, abi: fxDeskAbi, chainId: network.chainId } as const
  const query = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...desk, functionName: 'rate' },
      { ...desk, functionName: 'feeBps' },
      { ...desk, functionName: 'maxAmountPerSwap' },
      { ...desk, functionName: 'paused' },
      { ...desk, functionName: 'owner' },
      { ...desk, functionName: 'usdc' },
      { ...desk, functionName: 'eurc' },
    ],
    query: { enabled: !!network.address, refetchInterval: POLL_MS },
  })
  const data = query.data
  return {
    isLoading: query.isLoading,
    refetch: query.refetch,
    rate: data?.[0],
    feeBps: data?.[1],
    maxAmount: data?.[2],
    paused: data?.[3],
    owner: data?.[4],
    usdc: data?.[5],
    eurc: data?.[6],
  }
}

/** Wallet token balances (ERC-20 view), USDC allowance for the desk, and desk inventory. */
export function useDeskBalances(usdc: Address | undefined, eurc: Address | undefined) {
  const { address } = useAccount()
  const { network } = useDeskNetwork()
  const deskAddress = network.address
  const ready = !!deskAddress && !!usdc && !!eurc
  const common = { chainId: network.chainId } as const

  const wallet = useReadContracts({
    allowFailure: false,
    contracts:
      deskAddress && usdc && eurc && address
        ? [
            { ...common, address: usdc, abi: erc20Abi, functionName: 'balanceOf', args: [address] },
            { ...common, address: eurc, abi: erc20Abi, functionName: 'balanceOf', args: [address] },
            { ...common, address: usdc, abi: erc20Abi, functionName: 'allowance', args: [address, deskAddress] },
          ]
        : [],
    query: { enabled: ready && !!address, refetchInterval: POLL_MS },
  })

  const inventory = useReadContracts({
    allowFailure: false,
    contracts:
      deskAddress && usdc && eurc
        ? [
            { ...common, address: deskAddress, abi: fxDeskAbi, functionName: 'inventory', args: [usdc] },
            { ...common, address: deskAddress, abi: fxDeskAbi, functionName: 'inventory', args: [eurc] },
          ]
        : [],
    query: { enabled: ready, refetchInterval: POLL_MS },
  })

  const w = wallet.data as readonly bigint[] | undefined
  const inv = inventory.data as readonly bigint[] | undefined
  return {
    usdcBalance: w?.[0],
    eurcBalance: w?.[1],
    allowance: w?.[2],
    deskUsdc: inv?.[0],
    deskEurc: inv?.[1],
    refetch: async () => {
      await Promise.all([wallet.refetch(), inventory.refetch()])
    },
  }
}
