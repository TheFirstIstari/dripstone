defmodule DripstoneWeb.ModeController do
  @moduledoc """
  Switches the session between the Live and Demo datasets (`POST /mode`), then
  sends the analyst back to the page they were on. See `Dripstone.Tracker.dataset/0`.
  """
  use DripstoneWeb, :controller

  def update(conn, %{"mode" => mode}) when mode in ["live", "demo"] do
    conn
    |> put_session(:data_mode, mode)
    |> redirect(to: back_path(conn))
  end

  def update(conn, _params), do: redirect(conn, to: back_path(conn))

  # Same-site path from the Referer, so the switch keeps the analyst on the same
  # screen; anything else (missing, external, protocol-relative) goes to "/".
  defp back_path(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{path: "/" <> _ = path, query: query} <- URI.parse(referer),
         false <- String.starts_with?(path, "//") do
      if query, do: path <> "?" <> query, else: path
    else
      _ -> "/"
    end
  end
end
