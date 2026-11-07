<!-- Contract doc for the alert-intake capability; the catalog entry is exercised by tests. -->
# Adding an alert trigger type

A **trigger type** is a kind of alert that detection can raise, such as "Promotion
shift". The app only keeps each type's id, display name and one-sentence
description, for labels and filters. The detection logic for a type lives on the
detection side, which reports findings tagged with the type's id.

Built in: `new_network`, `network_growth`, `network_reactivation`, `promotion_shift`.

## 1. Add a catalog entry

Append an entry to the list in `config/config.exs`. The order here is the display order:

```elixir
config :dripstone, Dripstone.Alerts,
  trigger_types: [
    # ...existing entries...
    [
      id: "link_rotation",
      name: "Link rotation",
      description: "A network is cycling through many short-lived links."
    ]
  ]
```

- **`id`**: a stable lowercase string with underscores. Detection reports findings
  with this id, so never rename it once in use.
- **`name`**: shown in alert labels and filters.
- **`description`**: one sentence, ending with a full stop.

## 2. Tell detection about the id

Give the id to whoever owns the detector that will raise it. Findings that name an id
which isn't in the catalog are rejected.

## 3. Check it

```sh
mix test test/dripstone/alerts_test.exs
```

The existing test lists the built-in types in order; add your entry to it.
`Dripstone.Alerts.trigger_types/0` and `Dripstone.Alerts.get_trigger_type("link_rotation")`
now include the new type.
