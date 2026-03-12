defmodule BravoCreditWeb.Router do
  use BravoCreditWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BravoCreditWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug BravoCreditWeb.Plugs.AuthenticateUser
  end

  scope "/", BravoCreditWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  scope "/", BravoCreditWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/api", BravoCreditWeb do
    pipe_through :api

    post "/applications", ApplicationController, :create
    post "/webhooks/provider", WebhookController, :provider
  end

  scope "/api", BravoCreditWeb do
    pipe_through [:api, :authenticated_api]

    get "/applications", ApplicationController, :index
    get "/applications/:id", ApplicationController, :show
    patch "/applications/:id/state", ApplicationController, :update_state
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:bravo_credit, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BravoCreditWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
