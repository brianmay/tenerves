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

  defmodule Initial do
    def get_initial_token(email, password) do
      Application.ensure_all_started(:mojito)
      {:ok, token} = ExTesla.get_token(email, password)
      token
    end
  end

  @initial_token Initial.get_initial_token(
                   System.get_env("TESLA_EMAIL"),
                   System.get_env("TESLA_PASSWORD")
                 )
  @filename Application.get_env(:tenerves, :tesla_token_file)

  def get_token(nil) do
    if File.exists?(@filename) do
      with {:ok, data} <- File.read(@filename),
           {:ok, token} <- Jason.decode(data) do
        token =
          Map.new(token, fn {key, value} ->
            {String.to_atom(key), value}
          end)

        token = struct(ExTesla.Api.Token, token)

        token =
          cond do
            token.created_at > @initial_token.created_at -> token
            true -> @initial_token
          end

        {:ok, token}
      else
        {:error, error} -> {:error, error}
      end
    else
      {:ok, @initial_token}
    end
  end

  def get_token(%ExTesla.Api.Token{} = token), do: {:ok, token}

  def save_token(%ExTesla.Api.Token{} = token) do
    File.write(@filename, token |> Jason.encode!())
    :ok
  end

  def get_vehicle_by_vin(token, vin) do
    case ExTesla.list_all_vehicles(token) do
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

  defp get_prev_entry(vehicle) do
    previous_query =
      from(h in TeNerves.History,
        where: h.vin == ^vehicle["vin"],
        order_by: [desc: h.date_time],
        limit: 1
      )

    TeNerves.Repo.one(previous_query)
  end

  defp get_new_entry(vehicle, previous_state, date_time) do
    vehicle_state = vehicle["vehicle_state"]
    charge_state = vehicle["charge_state"]
    climate_state = vehicle["climate_state"]
    drive_state = vehicle["drive_state"]
    battery_level = charge_state["battery_level"]

    estimated_charge_duration = TeNerves.Estimator.my_charge_time(battery_level)
    battery_charge_time = Timex.Duration.to_hours(estimated_charge_duration)

    state = %TeNerves.History{
      vin: vehicle["vin"],
      date_time: date_time,
      odometer: ExTesla.convert_miles_to_km(vehicle_state["odometer"]),
      charge_energy_added: charge_state["charge_energy_added"],
      time_to_full_charge: charge_state["time_to_full_charge"],
      battery_charge_time: battery_charge_time,
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

    if is_nil(previous_state) do
      state
    else
      delta_time = DateTime.diff(state.date_time, previous_state.date_time)
      delta_odometer = state.odometer - previous_state.odometer

      delta_charge_energy_added =
        cond do
          state.charge_energy_added == 0.0 -> 0.0
          state.charge_energy_added < previous_state.charge_energy_added -> 0.0
          true -> state.charge_energy_added - previous_state.charge_energy_added
        end

      %TeNerves.History{
        state
        | delta_time: delta_time,
          delta_odometer: delta_odometer,
          delta_charge_energy_added: delta_charge_energy_added
      }
    end
  end

  defp process_vehicle_data(date_time, vehicle) do
    previous_state = get_prev_entry(vehicle)
    new_state = get_new_entry(vehicle, previous_state, date_time)

    state =
      case TeNerves.Repo.insert(new_state) do
        {:ok, state} ->
          state

        {:error, msg} ->
          Logger.error("Error inserting record #{msg}.")
          new_state
      end

    car_state = %{
      vehicle: vehicle,
      history: state
    }

    {:ok, car_state}
  end

  def poll_tesla(token, vin, tries \\ 3)

  def poll_tesla(_token, _vin, 0) do
    Logger.warn("Error polling Tesla too many retries.")
    {:error, "Too many failed attempts"}
  end

  def poll_tesla(token, vehicle, tries) do
    case ExTesla.get_vehicle_data(token, vehicle) do
      {:ok, vehicle} ->
        date_time = DateTime.utc_now()
        process_vehicle_data(date_time, vehicle)

      {:error, msg} ->
        Logger.warn("Error polling Tesla #{msg}, retrying #{tries - 1}.")
        poll_tesla(token, vehicle, tries - 1)
    end
  end
end
