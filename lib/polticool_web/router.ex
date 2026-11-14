defmodule PolticoolWeb.Router do
  use PolticoolWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PolticoolWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PolticoolWeb do
    pipe_through :browser

    live "/", IssuesLive
    live "/ballot", BallotLive
    live "/races/:key/compare", CompareLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", PolticoolWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:polticool, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PolticoolWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    # Design tokens + shared components, rendered in the real app shell
    scope "/dev", PolticoolWeb do
      pipe_through :browser

      get "/ui", PageController, :ui
    end
  end
end
