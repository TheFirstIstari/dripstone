defmodule DripstoneWeb.PageController do
  use DripstoneWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
