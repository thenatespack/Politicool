defmodule PolticoolWeb.PageController do
  use PolticoolWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
