use Mix.Config

config :tzdata, :data_dir, "/root/elixir_tzdata_data"

config :tenerves,
  tesla_token_file: "/root/token.json"

config :tenerves, TeNerves.Repo, url: System.get_env("PROD_DATABASE_URL")
