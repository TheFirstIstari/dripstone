defmodule Dripstone.Tracker.StoreWriteTest do
  # Changes the app-wide store, so it must not run alongside other tests.
  use Dripstone.DataCase, async: false

  alias Dripstone.Tracker
  alias Dripstone.Tracker.Store

  test "write/1 serializes concurrent writers so no update is lost" do
    counter = :atomics.new(1, [])

    tasks =
      for _ <- 1..20 do
        Task.async(fn ->
          Store.write(fn ->
            # Read-modify-write with a widened race window: without the lock,
            # tasks interleave here and increments get lost.
            value = :atomics.get(counter, 1)
            Process.sleep(2)
            :atomics.put(counter, 1, value + 1)
          end)
        end)
      end

    Enum.each(tasks, &Task.await(&1, 15_000))
    assert :atomics.get(counter, 1) == 20
  end

  test "concurrent Tracker changes serialize and keep every write" do
    Tracker.reset_sample_data!()

    tasks =
      for i <- 1..5 do
        Task.async(fn -> Tracker.add_note("net-c0421", %{"body" => "Note #{i}"}) end)
      end

    assert Enum.all?(tasks, &match?({:ok, _}, Task.await(&1, 15_000)))

    bodies =
      Tracker.get_network("net-c0421").notes
      |> Enum.map(& &1.body)
      |> MapSet.new()

    assert MapSet.subset?(MapSet.new(for(i <- 1..5, do: "Note #{i}")), bodies)
  end
end
