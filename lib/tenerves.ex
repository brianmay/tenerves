defmodule TeNerves do
  @moduledoc """
  Documentation for TeNerves.
  """
  import Ecto.Query
  require Logger

  defp decimal(nil), do: nil
  defp decimal(v), do: Decimal.new(v)

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

  def process_state(vehicle, vehicle_state, charge_state, climate_state, drive_state) do
    state = %TeNerves.History{
      vin: vehicle["vin"],
      date_time: DateTime.utc_now(),
      odometer: ExTesla.convert_miles_to_km(vehicle_state["odometer"]),
      charge_energy_added: decimal(charge_state["charge_energy_added"]),
      time_to_full_charge: decimal(charge_state["time_to_full_charge"]),
      battery_level: charge_state["battery_level"],
      est_battery_range: ExTesla.convert_miles_to_km(charge_state["est_battery_range"]),
      ideal_battery_range: ExTesla.convert_miles_to_km(charge_state["ideal_battery_range"]),
      battery_range: ExTesla.convert_miles_to_km(charge_state["battery_range"]),
      outside_temp: decimal(climate_state["outside_temp"]),
      inside_temp: decimal(climate_state["inside_temp"]),
      heading: drive_state["heading"],
      latitude: drive_state["latitude"],
      longitude: drive_state["longitude"],
      speed: ExTesla.convert_miles_to_km(drive_state["speed"])
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
        delta_odometer = Decimal.sub(state.odometer, previous_state.odometer)

        delta_charge_energy_added =
          if state.charge_energy_added == 0.0 do
            0.0
          else
            Decimal.sub(state.charge_energy_added, previous_state.charge_energy_added)
          end

        %TeNerves.History{
          state
          | delta_time: delta_time,
            delta_odometer: delta_odometer,
            delta_charge_energy_added: delta_charge_energy_added
        }
      end

    battery_left = state.ideal_battery_range
    battery_charge_km = Decimal.sub(384, battery_left)
    battery_charge_time = Decimal.div(battery_charge_km, 36) |> Decimal.round(2)

    state = %TeNerves.History{
      state
      | battery_charge_time: battery_charge_time
    }

    TeNerves.Repo.insert(state)
  end

  def poll_tesla(client, vin) do
    with {:ok, vehicle} <- get_vehicle_by_vin(client, vin),
         {:ok, vehicle_state} <- ExTesla.get_vehicle_state(client, vehicle),
         {:ok, charge_state} <- ExTesla.get_charge_state(client, vehicle),
         {:ok, climate_state} <- ExTesla.get_climate_state(client, vehicle),
         {:ok, drive_state} <- ExTesla.get_drive_state(client, vehicle) do
      process_state(vehicle, vehicle_state, charge_state, climate_state, drive_state)
    else
      {:error, msg} -> {:error, msg}
    end
  end
end
