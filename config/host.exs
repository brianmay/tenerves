use Mix.Config

config :tenerves,
  ca_cert_file: Path.join(["./rootfs_overlay", System.get_env("CA_CERT_FILE")]),
  tesla_token_file: "./token.json"

config :tenerves, TeNerves.Repo, url: System.get_env("HOST_DATABASE_URL")
