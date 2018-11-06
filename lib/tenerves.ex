defmodule TeNerves do
  @moduledoc """
  Documentation for TeNerves.
  """
  import Ecto.Query
  require Logger

  defmodule CarState do
    @enforce_keys [:vehicle, :history]
    defstruct [:vehicle, :history]
  end

  defp get_vehicle_by_vin(client, vin) do
    case ExTesla.list_all_vehicles(client) do
      {:ok, result} ->
        result = Enum.filter(result, fn vehicle -> vehicle["vin"] == vin end)

        case length(result) do
          1 -> {:ok, hd(result)}
          0 -> {:error, "Cannot find vehicle #{vin}."}
          l -> {:error, "Got too many results looking for #{vin}, got #{l} results."}
        end

      {:error, msg} ->
        {:error, msg}
    end
  end

  def process_state(vehicle) do
    vehicle_state = vehicle["vehicle_state"]
    charge_state = vehicle["charge_state"]
    climate_state = vehicle["climate_state"]
    drive_state = vehicle["drive_state"]

    date_time = DateTime.utc_now()

    state = %TeNerves.History{
      vin: vehicle["vin"],
      date_time: date_time,
      odometer: ExTesla.convert_miles_to_km(vehicle_state["odometer"]),
      charge_energy_added: charge_state["charge_energy_added"],
      time_to_full_charge: charge_state["time_to_full_charge"],
      battery_level: charge_state["battery_level"],
      est_battery_range: ExTesla.convert_miles_to_km(charge_state["est_battery_range"]),
      ideal_battery_range: ExTesla.convert_miles_to_km(charge_state["ideal_battery_range"]),
      battery_range: ExTesla.convert_miles_to_km(charge_state["battery_range"]),
      outside_temp: climate_state["outside_temp"],
      inside_temp: climate_state["inside_temp"],
      heading: drive_state["heading"],
      latitude: drive_state["latitude"],
      longitude: drive_state["longitude"],
      speed: ExTesla.convert_miles_to_km(drive_state["speed"]),
      inserted_at: date_time,
      updated_at: date_time
    }

    previous_query =
      from(h in TeNerves.History,
        where: h.vin == ^vehicle["vin"],
        order_by: [desc: h.date_time],
        limit: 1
      )

    previous_state = TeNerves.Repo.one(previous_query)

    state =
      if is_nil(previous_state) do
        state
      else
        delta_time = DateTime.diff(state.date_time, previous_state.date_time)
        delta_odometer = state.odometer - previous_state.odometer

        delta_charge_energy_added =
          if state.charge_energy_added == 0.0 do
            0.0
          else
            state.charge_energy_added - previous_state.charge_energy_added
          end

        %TeNerves.History{
          state
          | delta_time: delta_time,
            delta_odometer: delta_odometer,
            delta_charge_energy_added: delta_charge_energy_added
        }
      end

    battery_left = state.ideal_battery_range
    battery_charge_km = 384 - battery_left
    battery_charge_time = battery_charge_km / 36

    state = %TeNerves.History{
      state
      | battery_charge_time: battery_charge_time
    }

    state =
      case TeNerves.Repo.insert(state) do
        {:ok, new_state} ->
          new_state

        {:error, msg} ->
          Logger.error("Error inserting record #{msg}.")
          state
      end

    car_state = %{
      vehicle: vehicle,
      history: state
    }

    {:ok, car_state}
  end

  def poll_tesla(client, vin) do
    with {:ok, vehicle} <- get_vehicle_by_vin(client, vin),
         {:ok, vehicle} <- ExTesla.get_vehicle_data(client, vehicle) do
      process_state(vehicle)
    else
      {:error, msg} -> {:error, msg}
    end
  end
end
