defmodule BravoCredit.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BravoCreditWeb.Telemetry,
      BravoCredit.Repo,
      {DNSCluster, query: Application.get_env(:bravo_credit, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BravoCredit.PubSub},
      # Start a worker by calling: BravoCredit.Worker.start_link(arg)
      # {BravoCredit.Worker, arg},
      # Start to serve requests, typically the last entry
      BravoCreditWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BravoCredit.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BravoCreditWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
