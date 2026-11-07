defmodule Dripstone.Tracker.FindingTest do
  use ExUnit.Case, async: true

  import Dripstone.TrackerFixtures

  alias Dripstone.Tracker.{Evidence, Finding, Intake}

  @networks %{"net-known" => :exists}

  defp cast(attrs), do: Finding.cast(attrs, @networks)

  describe "valid findings" do
    test "a new network finding with atom keys" do
      assert {:ok, %Finding{} = f} = cast(new_network_finding())
      assert f.trigger_id == "new_network"
      assert f.severity == :high
      assert f.observed_at == t0()
      assert f.new_network.id == "net-1"

      assert [%Evidence{strength: :strong, kind: :shared_link, account_ids: ["a1", "a2"]}] =
               f.evidence
    end

    test "the same finding as decoded JSON (string keys, ISO dates)" do
      json =
        new_network_finding(%{
          ai_rationale: %{text: "Looks coordinated.", generated_at: t0()},
          comparison: %{label: "Members", before: "3", after: "5"}
        })
        |> stringify()

      assert {:ok, %Finding{} = f} = cast(json)
      assert f.severity == :high
      assert f.ai_rationale == %{text: "Looks coordinated.", generated_at: t0()}
      assert f.comparison.after == "5"
    end

    test "a finding for a known network with updates" do
      attrs =
        finding("net-known", %{network_updates: %{add_member_ids: ["a9", "a9"], confidence: 90}})

      assert {:ok, %Finding{network_id: "net-known", network_updates: updates}} = cast(attrs)
      assert updates.add_member_ids == ["a9"]
      assert updates.confidence == 90
    end

    test "unknown evidence kinds become :other instead of new atoms" do
      attrs = new_network_finding(%{evidence: [evidence(%{kind: "brand_new_kind"})]})
      assert {:ok, %Finding{evidence: [%Evidence{kind: :other}]}} = cast(attrs)
    end
  end

  describe "rejected findings" do
    for {name, attrs, field, message} <- [
          {"unknown trigger", %{trigger: "does-not-exist"}, :trigger,
           "unknown trigger \"does-not-exist\""},
          {"no evidence", %{evidence: []}, :evidence, "must contain at least one item"},
          {"missing evidence", %{evidence: nil}, :evidence, "must contain at least one item"},
          {"invalid severity", %{severity: "critical"}, :severity, "must be low, medium or high"},
          {"missing title", %{title: nil}, :title, "can't be blank"},
          {"missing observed_at", %{observed_at: nil}, :observed_at, "can't be blank"},
          {"bad observed_at", %{observed_at: "yesterday"}, :observed_at, "is invalid"}
        ] do
      test "#{name}" do
        attrs = new_network_finding(unquote(Macro.escape(attrs)))
        assert {:error, errors} = cast(attrs)
        assert unquote(message) in Map.fetch!(errors, unquote(field))
      end
    end

    test "evidence items must have an explanation and a valid strength" do
      assert {:error, %{evidence: ["item 1: strength must be weak, moderate or strong"]}} =
               cast(new_network_finding(%{evidence: [evidence(%{strength: "huge"})]}))

      assert {:error, %{evidence: ["item 2: explanation can't be blank"]}} =
               cast(new_network_finding(%{evidence: [evidence(), evidence(%{explanation: " "})]}))
    end

    test "unknown network" do
      assert {:error, %{network_id: ["unknown network \"net-nope\""]}} = cast(finding("net-nope"))
    end

    test "must name exactly one of network_id and new_network" do
      neither = Map.delete(new_network_finding(), :new_network)
      assert {:error, %{network_id: ["give network_id or new_network"]}} = cast(neither)

      both = Map.put(new_network_finding(), :network_id, "net-known")
      assert {:error, %{network_id: ["give network_id or new_network, not both"]}} = cast(both)
    end

    test "a new network must not reuse an existing id and needs members and confidence" do
      taken =
        new_network_finding(%{
          new_network: %{id: "net-known", name: "x", member_ids: ["a"], confidence: 50}
        })

      assert {:error, %{new_network: ["network \"net-known\" already exists"]}} = cast(taken)

      no_members =
        new_network_finding(%{new_network: %{id: "n", name: "x", member_ids: [], confidence: 50}})

      assert {:error, %{new_network: ["member_ids must be a non-empty list of strings"]}} =
               cast(no_members)

      bad_confidence =
        new_network_finding(%{
          new_network: %{id: "n", name: "x", member_ids: ["a"], confidence: 150}
        })

      assert {:error, %{new_network: ["confidence must be an integer from 0 to 100"]}} =
               cast(bad_confidence)
    end

    test "unknown member ids are rejected when accounts are known" do
      accounts = %{"a1" => :known}

      new_attrs =
        new_network_finding(%{
          new_network: %{id: "n", name: "x", member_ids: ["a1", "ghost"], confidence: 50}
        })

      assert {:error, %{new_network: ["unknown account \"ghost\""]}} =
               Finding.cast(new_attrs, @networks, accounts)

      update_attrs = finding("net-known", %{network_updates: %{add_member_ids: ["ghost"]}})

      assert {:error, %{network_updates: ["unknown account \"ghost\""]}} =
               Finding.cast(update_attrs, @networks, accounts)

      known_attrs =
        new_network_finding(%{
          new_network: %{id: "n", name: "x", member_ids: ["a1"], confidence: 50}
        })

      assert {:ok, _} = Finding.cast(known_attrs, @networks, accounts)
    end

    test "network_updates are only allowed for an existing network" do
      attrs = new_network_finding(%{network_updates: %{confidence: 90}})
      assert {:error, %{network_updates: ["only apply to an existing network_id"]}} = cast(attrs)
    end

    test "malformed optional details" do
      assert {:error, %{comparison: [_]}} =
               cast(new_network_finding(%{comparison: %{label: "Members", before: "3"}}))

      assert {:error, %{ai_rationale: ["generated_at must be an ISO 8601 date-time"]}} =
               cast(new_network_finding(%{ai_rationale: %{text: "hi", generated_at: "soon"}}))
    end

    test "mixed atom and string keys, or a non-map, are rejected without raising" do
      mixed = Map.put(new_network_finding(), "title", "also a title")
      assert {:error, %{base: ["keys must be all atoms or all strings"]}} = cast(mixed)
      assert {:error, %{base: ["a finding must be a map"]}} = Finding.cast("nope", @networks)
    end

    test "several problems are reported together" do
      attrs = new_network_finding(%{trigger: "nope", severity: "x", evidence: []})
      assert {:error, errors} = cast(attrs)
      assert Map.keys(errors) |> Enum.sort() == [:evidence, :severity, :trigger]
    end
  end

  describe "rejection leaves state unchanged" do
    test "Intake.run returns only the errors, never a new state" do
      state = state_with_network()

      assert {:error, %{trigger: _}} =
               Intake.run(state, finding("net-1", %{trigger: "nope"}), at(2))

      assert {:error, %{network_id: _}} = Intake.run(state, finding("net-missing"), at(2))
    end
  end
end
