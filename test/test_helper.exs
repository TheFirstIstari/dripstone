ExUnit.start()
# Zero-network CI: unstubbed Req calls raise instead of hitting the network.
Dripstone.Test.HttpGuard.attach()
Ecto.Adapters.SQL.Sandbox.mode(Dripstone.Repo, :manual)
