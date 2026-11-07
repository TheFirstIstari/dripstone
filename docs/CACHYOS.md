# CachyOS dev setup

1. `mise install` (installs Erlang/Elixir/Node/Python).
2. `docker compose up -d` (starts postgres:17).
3. `mix deps.get`
4. `mix ecto.setup`
5. `INTERNAL_AI_URL=http://wsl-3090:8000/v1 mix phx.server`
6. Validate: `curl localhost:4000` returns 200; `curl $INTERNAL_AI_URL/models` lists Qwen model.
