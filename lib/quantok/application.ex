defmodule Quantok.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      QuantokWeb.Telemetry,
      Quantok.Repo,
      {DNSCluster, query: Application.get_env(:quantok, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Quantok.PubSub},
      {Registry, keys: :unique, name: Quantok.WorldRegistry},
      {DynamicSupervisor, name: Quantok.WorldSupervisor, strategy: :one_for_one},
      QuantokWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Quantok.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    QuantokWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
