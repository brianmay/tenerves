defmodule TeNerves.History do
  @moduledoc false

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime, usec: true]

  schema "history" do
    field(:vin, :string)
    field(:date_time, :utc_datetime)
    field(:odometer, :decimal)
    field(:charge_energy_added, :decimal)
    field(:time_to_full_charge, :decimal)
    field(:battery_level, :integer)
    field(:est_battery_range, :decimal)
    field(:ideal_battery_range, :decimal)
    field(:battery_range, :decimal)
    field(:outside_temp, :decimal)
    field(:inside_temp, :decimal)
    field(:heading, :integer)
    field(:latitude, :float)
    field(:longitude, :float)
    field(:speed, :decimal)
    field(:delta_time, :integer)
    field(:delta_odometer, :decimal)
    field(:delta_charge_energy_added, :decimal)
    field(:battery_charge_time, :decimal)
    timestamps()
  end
end
