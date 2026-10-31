import { useAccount } from 'wagmi'
import { ConnectKitButton } from 'connectkit'
import { ArrowLeftRight } from 'lucide-react'
import { DESK_NETWORKS, chainName } from '@/lib/desk'
import { useDeskNetwork } from '@/lib/network'
import { shortAddress } from '@/lib/format'

function NetworkSwitch() {
  const { network, select, switching } = useDeskNetwork()
  return (
    <div
      role="group"
      aria-label="Network"
      className="inline-flex rounded-full p-1"
      style={{ background: 'var(--surface)', border: '1px solid var(--border)' }}
    >
      {DESK_NETWORKS.map((item) => {
        const active = item.chainId === network.chainId
        const dot = item.kind === 'testnet' ? 'var(--success)' : 'var(--warn)'
        return (
          <button
            key={item.chainId}
            aria-pressed={active}
            disabled={switching}
            onClick={() => select(item.chainId)}
            className="inline-flex min-h-9 items-center gap-2 rounded-full px-3 text-xs font-semibold transition-colors"
            style={{
              background: active ? 'var(--accent)' : 'transparent',
              color: active ? 'var(--accent-ink)' : 'var(--muted)',
            }}
          >
            <span className="size-2 rounded-full" style={{ background: dot }} />
            {item.label}
          </button>
        )
      })}
    </div>
  )
}

export function Header() {
  const { isConnected } = useAccount()
  const { walletOnUnsupportedChain, walletChainId } = useDeskNetwork()

  return (
    <header className="mx-auto flex w-full max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-5 sm:px-6">
      <div className="flex items-center gap-3">
        <div
          className="flex size-10 items-center justify-center rounded-xl"
          style={{ background: 'var(--accent)', color: 'var(--accent-ink)' }}
        >
          <ArrowLeftRight className="size-5" />
        </div>
        <div>
          <h1 className="display text-lg font-bold leading-none">Arc FX Desk</h1>
          <p className="mt-1 text-xs" style={{ color: 'var(--subtle)' }}>
            USDC to EURC, quote first
          </p>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {isConnected && walletOnUnsupportedChain && (
          <span className="text-xs font-semibold" style={{ color: 'var(--danger)' }}>
            Wallet on {chainName(walletChainId)}
          </span>
        )}
        <NetworkSwitch />
        <ConnectKitButton.Custom>
          {({ isConnected: connected, show, address }) => (
            <button className="btn-primary px-5 text-sm" onClick={show}>
              {connected && address ? shortAddress(address) : 'Connect wallet'}
            </button>
          )}
        </ConnectKitButton.Custom>
      </div>
    </header>
  )
}
