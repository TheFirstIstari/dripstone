# Dripstone

## Setup

* `mise install` — install pinned toolchain
* `mise run db-up` — start Postgres
* `mise run db-setup` — create/migrate/seed the database
* `mise run dev` — start the Phoenix endpoint at [`localhost:4000`](http://localhost:4000)
* `mise run test` — run tests
* `mise run ci` — mirror CI (lint + build + test)
* `mise tasks ls` — discover all commands
* See `docs/CACHYOS.md` for CachyOS workstation notes

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
