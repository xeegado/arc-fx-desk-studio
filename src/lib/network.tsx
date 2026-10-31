import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react'
import { useAccount, useSwitchChain } from 'wagmi'
import { DESK_NETWORKS, TESTNET, getDeskNetwork, type DeskNetwork } from '@/lib/desk'

interface NetworkState {
  /** The network the app is reading from and transacting on. */
  network: DeskNetwork
  /** True when a wallet is connected on a chain the desk does not support. */
  walletOnUnsupportedChain: boolean
  /** Wallet chain id, when connected. */
  walletChainId: number | undefined
  switching: boolean
  select: (chainId: number) => void
}

const NetworkContext = createContext<NetworkState | undefined>(undefined)

/** Follows the wallet's chain when it is an Arc network, otherwise the user's last selection. */
export function NetworkProvider({ children }: { children: ReactNode }) {
  const { isConnected, chainId } = useAccount()
  const { switchChain, isPending } = useSwitchChain()
  const [selected, setSelected] = useState<DeskNetwork>(TESTNET)

  const walletNetwork = isConnected ? getDeskNetwork(chainId) : undefined
  const network = walletNetwork ?? selected

  const select = useCallback(
    (target: number) => {
      const next = DESK_NETWORKS.find((item) => item.chainId === target)
      if (!next) return
      setSelected(next)
      if (isConnected && chainId !== target) switchChain({ chainId: target })
    },
    [isConnected, chainId, switchChain],
  )

  const value = useMemo<NetworkState>(
    () => ({
      network,
      walletOnUnsupportedChain: isConnected && !walletNetwork,
      walletChainId: isConnected ? chainId : undefined,
      switching: isPending,
      select,
    }),
    [network, isConnected, walletNetwork, chainId, isPending, select],
  )

  return <NetworkContext.Provider value={value}>{children}</NetworkContext.Provider>
}

export function useDeskNetwork(): NetworkState {
  const value = useContext(NetworkContext)
  if (!value) throw new Error('useDeskNetwork must be used inside NetworkProvider')
  return value
}
