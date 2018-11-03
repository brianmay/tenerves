defmodule TeNerves.History do
  @moduledoc false

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime, usec: true]

  schema "history" do
    field(:vin, :string)
    field(:date_time, :utc_datetime)
    field(:odometer, :float)
    field(:charge_energy_added, :float)
    field(:time_to_full_charge, :float)
    field(:battery_level, :integer)
    field(:est_battery_range, :float)
    field(:ideal_battery_range, :float)
    field(:battery_range, :float)
    field(:outside_temp, :float)
    field(:inside_temp, :float)
    field(:heading, :integer)
    field(:latitude, :float)
    field(:longitude, :float)
    field(:speed, :float)
    field(:delta_time, :integer)
    field(:delta_odometer, :float)
    field(:delta_charge_energy_added, :float)
    field(:battery_charge_time, :float)
    timestamps()
  end
end
