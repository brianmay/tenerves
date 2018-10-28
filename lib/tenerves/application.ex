defmodule TeNerves.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  @target Mix.Project.config()[:target]
  @mqtt_host Application.get_env(:tenerves, :mqtt_host)
  @mqtt_port Application.get_env(:tenerves, :mqtt_port)

  use Application

  def start(_type, _args) do
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TeNerves.Supervisor]
    Supervisor.start_link(children(@target), opts)
  end

  def get_tortoise_client_id do
    {:ok, hostname} = :inet.gethostname()
    hostname = to_string(hostname)
    "tenerves-#{hostname}"
  end

  # List all child processes to be supervised
  def children(_target) do
    [
      # Starts a worker by calling: Tenerves.Worker.start_link(arg)
      # {Tenerves.Worker, arg},
      {TeNerves.Scheduler, []},
      {TeNerves.Repo, []},
      {TeNerves.Poller, name: TeNerves.Poller},
      {Tortoise.Connection,
       client_id: get_tortoise_client_id(),
       handler: {Tortoise.Handler.Logger, []},
       server: {Tortoise.Transport.Tcp, host: @mqtt_host, port: @mqtt_port},
       subscriptions: []}
    ]
  end
end
