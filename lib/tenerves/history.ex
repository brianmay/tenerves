defmodule TeNerves.History do
  @moduledoc false

  use Ecto.Schema
  @timestamps_opts [type: :utc_datetime_usec]

  @derive {Jason.Encoder,
           only: [
             :vin,
             :date_time,
             :odometer,
             :charge_energy_added,
             :time_to_full_charge,
             :battery_level,
             :est_battery_range,
             :ideal_battery_range,
             :battery_range,
             :outside_temp,
             :inside_temp,
             :heading,
             :latitude,
             :longitude,
             :speed,
             :delta_time,
             :delta_odometer,
             :delta_charge_energy_added,
             :battery_charge_time
           ]}

  schema "history" do
    field(:vin, :string)
    field(:date_time, :utc_datetime_usec)
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
