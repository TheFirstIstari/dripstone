# CachyOS dev setup

1. `mise install` (installs Erlang/Elixir/Node/Python).
2. `docker compose up -d` (starts postgres:17).
3. `mix deps.get`
4. `mix ecto.setup`
5. `mix phx.server` (AI calls go to the OpenCode Console `systemone` endpoint
   with a bearer key — never to a local vLLM host. Mint a Jev-scoped key in the
   Console and put `OPENCODE_API_KEY=<your-key>` in `.env`; endpoint/model
   defaults (`INTERNAL_AI_URL`, `INTERNAL_AI_MODEL`) come from `mise.toml`.
   Without a key, calls fail to `{:error, _}` and the app silently falls back
   to heuristics — if assessments look heuristic-only, check the key first.
   See README `## AI key`.)
6. Validate: `curl localhost:4000` returns 200.

## GitHub runner (deploy only)

- Labels: `self-hosted, Linux, X64, cachyos-x8664, deploy` — CI runs on
  GitHub-hosted `ubuntu-latest` so PR code never reaches this host.
- Register once on the CachyOS host:
  `./config.sh --url https://github.com/TheFirstIstari/dripstone --name cachyos-x64-01 --labels self-hosted,Linux,X64,cachyos-x8664,deploy`
  Get the token from repo Settings → Actions → Runners → New runner; never commit it.
- Manage: `sudo ./svc.sh status`, `sudo ./svc.sh start` (after `./svc.sh install`).
- Enable systemd on boot so the runner survives reboot.

## Transfer 3 hosts to dripstone

Capacity: 6 `cachyos-x8664` hosts total. Move hosts 4-6 to dripstone,
leave 1-3 on irc-serve.

1. GitHub dripstone Settings → Actions → Runners → New self-hosted
   runner → copy token (fresh token per host — tokens are single-use, ~1h life;
   get each via repo Settings → Actions → Runners → New runner, or
   `gh api --method POST repos/TheFirstIstari/dripstone/actions/runners/registration-token --jq .token` from a laptop).
2. On each of hosts 4-6 (keep same N):
   `sudo ./svc.sh stop; sudo ./svc.sh uninstall`
   `./config.sh remove --token <IRC-SERVE-REMOVE-TOKEN>`
   `mkdir ~/actions-runner-dripstone && cd ~/actions-runner-dripstone`
   `tar xzf ~/actions-runner.tar.gz -C .` (or re-download runner)
  `./config.sh --url https://github.com/TheFirstIstari/dripstone --token <DRIPSTONE-TOKEN> --labels self-hosted,Linux,X64,cachyos-x8664,deploy --name cachyos-x8664-N`
   `sudo ./svc.sh install <svc-user>; sudo ./svc.sh start`
   Use a distinct service name from the old irc-serve service.
3. DO NOT reuse the same work dir for two repos.
4. Validate: `gh api repos/TheFirstIstari/dripstone/actions/runners`.
