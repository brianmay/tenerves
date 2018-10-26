defmodule TeNerves.History do
  @moduledoc false

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime, usec: true]

  schema "history" do
    field(:date_time, :utc_datetime)
    field(:vehicle, :string)
    field(:odometer, :decimal)
    field(:charge_energy_added, :decimal)
    field(:time_to_full_charge, :decimal)
    field(:battery_level, :integer)
    field(:est_battery_range, :decimal)
    field(:ideal_battery_range, :decimal)
    field(:battery_range, :decimal)
    field(:outside_temp, :decimal)
    field(:inside_temp, :decimal)
    field(:heading, :decimal)
    field(:latitude, :float)
    field(:longitude, :float)
    field(:speed, :decimal)
    timestamps()
  end
end
