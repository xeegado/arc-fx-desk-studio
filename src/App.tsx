import { useAccount } from 'wagmi'
import { AlertTriangle } from 'lucide-react'
import { AdminPanel } from '@/components/AdminPanel'
import { BalanceCards } from '@/components/BalanceCards'
import { Header } from '@/components/Header'
import { HistoryTable } from '@/components/HistoryTable'
import { SwapCard } from '@/components/SwapCard'
import { useDeskBalances, useDeskState } from '@/hooks/useDesk'
import { useHistory } from '@/hooks/useHistory'
import { chainName } from '@/lib/desk'
import { NetworkProvider, useDeskNetwork } from '@/lib/network'
import { buildAddressExplorerUrl } from '@/onchain-facts'
import { shortAddress } from '@/lib/format'

function Notice({ tone, children }: { tone: 'warn' | 'danger'; children: React.ReactNode }) {
  const color = tone === 'warn' ? '232,196,109' : '232,109,122'
  return (
    <div
      className="flex items-start gap-3 rounded-2xl px-4 py-3 text-sm"
      style={{ background: `rgba(${color},0.1)`, border: `1px solid rgba(${color},0.35)` }}
      role="status"
    >
      <AlertTriangle className="mt-0.5 size-4 shrink-0" style={{ color: `rgb(${color})` }} />
      <span style={{ color: 'var(--ink-2)' }}>{children}</span>
    </div>
  )
}

function NotDeployed({ label, variable }: { label: string; variable: string }) {
  return (
    <div className="panel mx-auto max-w-lg p-8 text-center">
      <h2 className="display text-xl font-semibold">Desk not deployed on {label}</h2>
      <p className="mt-2 text-sm" style={{ color: 'var(--subtle)' }}>
        No desk contract address is configured for this network. Set {variable} and restart the dev server.
      </p>
    </div>
  )
}

function Desk() {
  const { address, isConnected } = useAccount()
  const { network, walletOnUnsupportedChain, walletChainId } = useDeskNetwork()
  const desk = useDeskState()
  const balances = useDeskBalances(desk.usdc, desk.eurc)
  const history = useHistory()

  const ready = isConnected && !walletOnUnsupportedChain
  const isOwner = !!address && !!desk.owner && address.toLowerCase() === desk.owner.toLowerCase()
  const variable = network.kind === 'mainnet' ? 'VITE_FX_DESK_MAINNET_ADDRESS' : 'VITE_FX_DESK_TESTNET_ADDRESS'

  const refresh = () => {
    void desk.refetch()
    void balances.refetch()
    void history.refetch()
  }

  return (
    <div className="min-h-dvh pb-20">
      <Header />

      <main className="mx-auto grid w-full max-w-6xl gap-5 px-4 sm:px-6">
        {walletOnUnsupportedChain && (
          <Notice tone="danger">
            Your wallet is on {chainName(walletChainId)}. Switch to {network.label} to request quotes and swap.
          </Notice>
        )}
        {network.kind === 'mainnet' && (
          <Notice tone="warn">Arc Mainnet uses real funds. Transactions are irreversible, so check every amount before you confirm.</Notice>
        )}

        {!network.address ? (
          <NotDeployed label={network.label} variable={variable} />
        ) : (
          <>
            <div className="grid items-start gap-5 lg:grid-cols-[minmax(0,460px)_minmax(0,1fr)]">
              <SwapCard
                key={network.chainId}
                usdc={desk.usdc}
                rate={desk.rate}
                feeBps={desk.feeBps}
                maxAmount={desk.maxAmount}
                paused={desk.paused}
                usdcBalance={balances.usdcBalance}
                allowance={balances.allowance}
                deskEurc={balances.deskEurc}
                onSettled={refresh}
              />
              <div className="grid gap-5">
                <BalanceCards
                  connected={ready}
                  usdcBalance={balances.usdcBalance}
                  eurcBalance={balances.eurcBalance}
                  deskUsdc={balances.deskUsdc}
                  deskEurc={balances.deskEurc}
                />
                {isOwner && desk.usdc && desk.eurc && ready && (
                  <AdminPanel
                    usdc={desk.usdc}
                    eurc={desk.eurc}
                    rate={desk.rate}
                    feeBps={desk.feeBps}
                    maxAmount={desk.maxAmount}
                    paused={desk.paused}
                    onChanged={refresh}
                  />
                )}
              </div>
            </div>

            <HistoryTable connected={ready} rows={history.data} loading={history.isLoading} failed={history.isError} />

            <p className="text-center text-xs" style={{ color: 'var(--subtle)' }}>
              Desk contract{' '}
              <a
                className="mono"
                style={{ color: 'var(--accent)' }}
                href={buildAddressExplorerUrl(network.chainId, network.address)}
                target="_blank"
                rel="noreferrer"
              >
                {shortAddress(network.address)}
              </a>{' '}
              on {network.label}
            </p>
          </>
        )}
      </main>
    </div>
  )
}

export default function App() {
  return (
    <NetworkProvider>
      <Desk />
    </NetworkProvider>
  )
}
