defmodule PolticoolWeb.LiveAcceptance do
  @moduledoc """
  Lets LiveView processes join a browser test's Ecto sandbox (phx_demo,
  phoenix_test_playwright). Does nothing unless `config :polticool, :sql_sandbox, true`.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:default, _params, _session, socket) do
    if Application.get_env(:polticool, :sql_sandbox) do
      socket =
        assign_new(socket, :phoenix_ecto_sandbox, fn ->
          if connected?(socket), do: get_connect_info(socket, :user_agent)
        end)

      Phoenix.Ecto.SQL.Sandbox.allow(
        socket.assigns.phoenix_ecto_sandbox,
        Ecto.Adapters.SQL.Sandbox
      )
    end

    {:cont, socket}
  end
end
