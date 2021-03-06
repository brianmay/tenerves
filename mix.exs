defmodule TeNerves.MixProject do
  use Mix.Project

  @app :tenerves
  @target System.get_env("MIX_TARGET") || "host"

  def project do
    [
      app: @app,
      version: "0.1.0",
      elixir: "~> 1.6",
      target: @target,
      archives: [nerves_bootstrap: "~> 1.6"],
      deps_path: "deps/#{@target}",
      build_path: "_build/#{@target}",
      lockfile: "mix.lock.#{@target}",
      start_permanent: Mix.env() == :prod,
      build_embedded: @target != "host",
      aliases: [loadconfig: [&bootstrap/1]],
      deps: deps(),
      releases: [{@app, release()}],
      preferred_cli_target: [run: :host, test: :host]
    ]
  end

  # Starting nerves_bootstrap adds the required aliases to Mix.Project.config()
  # Aliases are only added if MIX_TARGET is set.
  def bootstrap(args) do
    Application.start(:nerves_bootstrap)
    Mix.Task.run("loadconfig", args)
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {TeNerves.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nerves, "~> 1.5", runtime: false},
      {:shoehorn, "~> 0.6"},
      {:ring_logger, "~> 0.4"},
      {:timex, "~> 3.0"},
      {:ex_tesla, "~> 2.0"},
      {:ecto_sql, "~> 3.0"},
      {:postgrex, "~> 0.15"},
      {:tortoise, "~> 0.9.2"},
      {:jason, "~> 1.1"},
      {:geocalc,
       git: "https://github.com/yltsrc/geocalc", tag: "0bf0b3346f569c1fcf9df284230e7ba637ddc31a"},
      {:httpoison, "~> 1.6"}
    ] ++ deps(@target)
  end

  # Specify target specific dependencies
  defp deps("host"), do: []

  defp deps(target) do
    [
      {:nerves_runtime, "~> 0.6"},
      {:nerves_network, "~> 0.3"},
      {:nerves_time, "~> 0.3"},
      {:nerves_init_gadget, "~> 0.4"},
      {:dns, "~> 2.1.2"}
    ] ++ system(target)
  end

  def release do
    [
      overwrite: true,
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod
    ]
  end

  defp system("rpi"), do: [{:nerves_system_rpi, "~> 1.8", runtime: false}]
  defp system("rpi0"), do: [{:nerves_system_rpi0, "~> 1.8", runtime: false}]
  defp system("rpi2"), do: [{:nerves_system_rpi2, "~> 1.8", runtime: false}]
  defp system("rpi3"), do: [{:nerves_system_rpi3, "~> 1.8", runtime: false}]
  defp system("bbb"), do: [{:nerves_system_bbb, "~> 2.3", runtime: false}]
  defp system("ev3"), do: [{:nerves_system_ev3, "~> 1.8", runtime: false}]
  defp system("x86_64"), do: [{:nerves_system_x86_64, "~> 1.8", runtime: false}]
  defp system(target), do: Mix.raise("Unknown MIX_TARGET: #{target}")
end
