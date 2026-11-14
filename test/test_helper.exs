{:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
Application.put_env(:phoenix_test, :base_url, PolticoolWeb.Endpoint.url())
ExUnit.start(exclude: [:phx_demo])
Ecto.Adapters.SQL.Sandbox.mode(Polticool.Repo, :manual)
