defmodule TeNerves do
  @moduledoc """
  Documentation for TeNerves.
  """
  @output_directory Application.get_env(:tenerves, :output_directory)
  @vin Application.get_env(:tenerves, :vin)

  def poll_tesla(client, vin, previous_state) do
    {:ok, result} = ExTesla.list_all_vehicles(client)
    result = Enum.filter(result, fn vehicle -> vehicle["vin"] == vin end)
    1 = length(result)

    vehicle = hd(result)

    {:ok, vehicle_state} = ExTesla.get_vehicle_state(client, vehicle)
    {:ok, charge_state} = ExTesla.get_charge_state(client, vehicle)
    {:ok, climate_state} = ExTesla.get_climate_state(client, vehicle)
    {:ok, drive_state} = ExTesla.get_drive_state(client, vehicle)

    state = %{
      "date_time" => DateTime.utc_now,

      "vehicle" => vehicle["display_name"],

      "odometer" => ExTesla.convert_miles_to_km(vehicle_state["odometer"]),

      "charge_energy_added" => charge_state["charge_energy_added"],
      "time_to_full_charge" => charge_state["time_to_full_charge"],
      "battery_level" => charge_state["battery_level"],
      "est_battery_range" => ExTesla.convert_miles_to_km(charge_state["est_battery_range"]),
      "ideal_battery_range" => ExTesla.convert_miles_to_km(charge_state["ideal_battery_range"]),
      "battery_range" => ExTesla.convert_miles_to_km(charge_state["battery_range"]),

      "outside_temp" => climate_state["outside_temp"],
      "inside_temp" => climate_state["inside_temp"],

      "heading" => drive_state["heading"],
      "latitude" => drive_state["latitude"],
      "longitude" => drive_state["longitude"],
      "speed" => drive_state["speed"],
    }

    delta_time = DateTime.diff(state["date_time"], previous_state["date_time"])
    delta_odometer = Float.round(state["odometer"] - previous_state["odometer"], 1)
    delta_charge_energy_added = if state["charge_energy_added"] == 0.0 do
      0.0
    else
      Float.round(state["charge_energy_added"] - previous_state["charge_energy_added"], 2)
    end

    battery_left = state["ideal_battery_range"]
    battery_charge_km = 384 - battery_left
    battery_charge_time = Float.round(battery_charge_km / 36, 2)

    extra_data = %{
      "delta_time" => delta_time,
      "delta_odometer" => delta_odometer,
      "delta_charge_energy_added" => delta_charge_energy_added,
      "battery_charge_time" => battery_charge_time
    }

    {state, extra_data}
  end

  def poll_and_update() do
    vin = @vin

    state_file = Path.join([@output_directory, "state.json"])
    results_file = Path.join([@output_directory, "results.json"])

    {:ok, token} = ExTesla.get_token
    {:ok, token} = ExTesla.check_token(token)

    client = ExTesla.client(token)

    previous_state = File.read!(state_file) |> Jason.decode!()
    {state, extra_data} = poll_tesla(client, vin, previous_state)

    encoded = Jason.encode!(state) <> "\n"
    :ok = File.write(state_file, encoded)

    merged = Map.merge(state, extra_data)
    IO.inspect(merged)
    encoded = Jason.encode!(merged) <> "\n"
    :ok = File.write(results_file, encoded, [:append])
  end
end
