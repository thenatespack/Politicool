defmodule PolticoolWeb.PageController do
  use PolticoolWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  # Dev-only UI kit (routed under dev_routes in the router)
  def ui(conn, _params) do
    render(conn, :ui, page_title: "UI kit")
  end
end
