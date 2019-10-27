# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# Customize non-Elixir parts of the firmware. See
# https://hexdocs.pm/nerves/advanced-configuration.html for details.

config :nerves, :firmware, rootfs_overlay: "rootfs_overlay"

# Use shoehorn to start the main application. See the shoehorn
# docs for separating out critical OTP applications such as those
# involved with firmware updates.

config :shoehorn,
  init: [
    :nerves_runtime,
    :nerves_network,
    :nerves_time,
    :nerves_init_gadget,
    :postgrex,
    :tenerves
  ],
  app: Mix.Project.config()[:app]

config :nerves_network,
  regulatory_domain: "AU"

config :nerves_network, :default,
  wlan0: [
    ssid: System.get_env("NERVES_NETWORK_SSID"),
    psk: System.get_env("NERVES_NETWORK_PSK"),
    key_mgmt: String.to_atom(System.get_env("NERVES_NETWORK_MGMT"))
  ],
  eth0: [
    ipv4_address_method: :dhcp
  ]

config :nerves_time, :servers, [
  "0.pool.ntp.org",
  "1.pool.ntp.org",
  "2.pool.ntp.org",
  "3.pool.ntp.org"
]

config :nerves_firmware_ssh,
  authorized_keys: [
    "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAo9J3VtrQldIJeQR6ilEHLiYdOEOlanfKghN/ZOhd1B/TDD94vWo7R+M3shJDkPGR8qjPCGDUSZSg8G1bzPhMyAaTgLejdRk9yPt5Z/QmDs6rYk/RHCEl+9GTQEjBVbaUH0oeMsIiB1sgBzCj4Wcfd8cJwuWjzWQdwgMwApwOEV2Gpg6ZWDzfNVoe7YwgLZVvPngZCXNWQJ/9HRzXPEi1Nz0Gc2zciZS8FkrqG4VsWkRH8KT/4AJm0PWz7aY+OqnOF9Fn6hBwpnB3LO+a0HEFEbPdCB9V5ORH+xj6smkf/TMmq16oCexGyX3vbnKfKrRS5Vv5oxkjpHQyvemmG6gc6Q== /home/brian/.ssh/id_rsa"
  ]

config :nerves_init_gadget,
  ifname: "wlan0",
  mdns_domain: :hostname,
  ssh_console_port: 22,
  address_method: :dhcp

# Use Ringlogger as the logger backend and remove :console.
# See https://hexdocs.pm/ring_logger/readme.html for more information on
# configuring ring_logger.

config :logger, backends: [RingLogger]

config :logger, RingLogger, max_size: 2048

config :tenerves,
  vin: System.get_env("VIN"),
  ecto_repos: [TeNerves.Repo],
  mqtt_host: System.get_env("MQTT_HOST"),
  mqtt_port: String.to_integer(System.get_env("MQTT_PORT") || "8883"),
  ca_cert_file: System.get_env("CA_CERT_FILE"),
  mqtt_user_name: System.get_env("MQTT_USER_NAME"),
  mqtt_password: System.get_env("MQTT_PASSWORD"),
  home: [0, 0]

config :tenerves, TeNerves.Repo,
  url: System.get_env("DATABASE_URL"),
  migration_timestamps: [type: :utc_datetime_usec]

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

import_config "secrets.exs"
import_config "#{Mix.Project.config()[:target]}.exs"
