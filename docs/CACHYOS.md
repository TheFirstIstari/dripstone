# CachyOS dev setup

Follow the README setup (`.env` with `ANALYST_PASSWORD`, then `mise run
db-up`, `mise run db-setup`, `mise run dev`).

## GitHub runner (deploy only)

- Labels: `self-hosted, Linux, X64, cachyos-x8664, deploy` — only the deploy
  workflow targets this host; keep deployment credentials off CI runners.

- Register once on the CachyOS host:
  `./config.sh --url https://github.com/TheFirstIstari/dripstone --name cachyos-x64-01 --labels self-hosted,Linux,X64,cachyos-x8664,deploy`
  Get the token from repo Settings → Actions → Runners → New runner; never commit it.
- Manage: `sudo ./svc.sh status`, `sudo ./svc.sh start` (after `./svc.sh install`).
- Enable systemd on boot so the runner survives reboot.
