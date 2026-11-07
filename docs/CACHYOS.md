# CachyOS dev setup

1. `mise install` (installs Erlang/Elixir/Node/Python).
2. `docker compose up -d` (starts postgres:17).
3. `mix deps.get`
4. `mix ecto.setup`
5. `INTERNAL_AI_URL=http://desktop:8000/v1 mix phx.server`
6. Validate: `curl localhost:4000` returns 200; `curl $INTERNAL_AI_URL/models` lists Qwen model.

## GitHub runner

- Labels: `self-hosted, Linux, X64` (see `.github/workflows/ci.yml`).
- Register once on the CachyOS host:
  `./config.sh --url https://github.com/TheFirstIstari/dripstone --name cachyos-x64-01`
  Get the token from repo Settings → Actions → Runners → New runner; never commit it.
- Manage: `sudo ./svc.sh status`, `sudo ./svc.sh start` (after `./svc.sh install`).
- Enable systemd on boot so the runner survives reboot.
