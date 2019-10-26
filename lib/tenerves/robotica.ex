defmodule TeNerves.Robotica do
  @moduledoc false
  require Logger

  @home Application.get_env(:tenerves, :home)

  defmodule State do
    @enforce_keys [:is_home, :charger_plugged_in, :battery_level, :unlocked_time, :unlocked_delta]
    @derive Jason.Encoder
    defstruct [:is_home, :charger_plugged_in, :battery_level, :unlocked_time, :unlocked_delta]
  end

  defp is_after_time(utc_now, time) do
    threshold_time =
      utc_now
      |> Timex.Timezone.convert("Australia/Melbourne")
      |> Timex.set(time: time)
      |> Timex.Timezone.convert("Etc/UTC")

    Timex.compare(utc_now, threshold_time) >= 0
  end

  defp get_messages(state, previous_state, utc_now) do
    after_threshold = is_after_time(utc_now, ~T[20:00:00])

    day_of_week =
      utc_now
      |> Timex.Timezone.convert("Australia/Melbourne")
      |> Date.day_of_week()

    previous_unlocked_delta =
      cond do
        is_nil(previous_state) -> nil
        true -> previous_state.unlocked_delta
      end

    unlocked_delta = state.unlocked_delta

    rules = [
      {
        not is_nil(previous_state) and previous_state.is_home and not state.is_home,
        fn -> "The Tesla has left home." end
      },
      {
        not is_nil(previous_state) and not previous_state.is_home and state.is_home,
        fn -> "The Tesla has returned home." end
      },
      {
        not is_nil(unlocked_delta) and unlocked_delta >= 9 * 60,
        fn -> "The Tesla has been unlocked for #{div(unlocked_delta, 60)} minutes." end
      },
      {
        is_nil(unlocked_delta) and not is_nil(previous_unlocked_delta) and
          previous_unlocked_delta >= 9 * 60,
        fn ->
          "The Tesla has been locked after being unlocked " <>
            "for #{div(previous_unlocked_delta, 60)} minutes."
        end
      },
      {
        after_threshold and state.battery_level < 80 and not state.charger_plugged_in and
          state.is_home and day_of_week not in [4, 7],
        fn -> "The Tesla is not plugged in, please plug in the Tesla." end
      },
      {
        is_after_time(utc_now, ~T[21:30:00]) and state.battery_level < 80 and
          not state.charger_plugged_in and state.is_home and day_of_week in [4],
        fn -> "The Tesla is not plugged in, please plug in the Tesla." end
      },
      {
        is_after_time(utc_now, ~T[21:00:00]) and state.battery_level < 80 and
          not state.charger_plugged_in and state.is_home and day_of_week in [7],
        fn -> "The Tesla is not plugged in, please plug in the Tesla." end
      },
      {
        not is_nil(previous_state) and previous_state.charger_plugged_in and
          not state.charger_plugged_in,
        fn -> "The Tesla has been disconnected." end
      },
      {
        not is_nil(previous_state) and not previous_state.charger_plugged_in and
          state.charger_plugged_in,
        fn -> "The Tesla has been plugged in." end
      }
    ]

    rules
    |> Enum.filter(fn {cond, _} -> cond end)
    |> Enum.map(fn {_, msg} -> msg.() end)
  end

  defp log_messages(messages) do
    Enum.each(messages, fn message ->
      Logger.info("Got message: #{message}")
    end)

    messages
  end

  defp send_messages([]), do: nil

  defp send_messages(messages) do
    action = %{
      "locations" => ["Brian", "Dining"],
      "action" => %{
        "message" => %{"text" => Enum.join(messages, " ")}
      }
    }

    case Jason.encode(action) do
      {:ok, message} ->
        client_id = TeNerves.Application.get_tortoise_client_id()
        :ok = Tortoise.publish(client_id, "execute", message, qos: 0)

      {:error, _msg} ->
        Logger.error("Error encoding JSON.")
    end

    nil
  end

  def send_state(car_state, state) do
    history = car_state.history

    vehicle =
      car_state.vehicle
      |> Map.delete("tokens")
      |> Map.delete("id")
      |> Map.delete("id_s")

    state_message = %{
      "vehicle" => vehicle,
      "history" => history,
      "state" => state
    }

    case Jason.encode(state_message) do
      {:ok, message} ->
        client_id = TeNerves.Application.get_tortoise_client_id()
        :ok = Tortoise.publish(client_id, "tesla", message, qos: 0)

      {:error, _msg} ->
        Logger.error("Error encoding JSON.")
    end

    nil
  end

  def get_state(car_state, previous_state, utc_now) do
    vehicle_state = car_state.vehicle["vehicle_state"]
    drive_state = car_state.vehicle["drive_state"]
    charge_state = car_state.vehicle["charge_state"]

    point = %{
      latitude: drive_state["latitude"],
      longitude: drive_state["longitude"]
    }

    charger_plugged_in =
      case {charge_state["charging_state"], previous_state} do
        {nil, nil} -> false
        {nil, _} -> previous_state.charger_plugged_in
        {"Disconnected", _} -> false
        _ -> true
      end

    previous_unlocked_time =
      case previous_state do
        nil -> nil
        state -> state.unlocked_time
      end

    unlocked_time =
      case {vehicle_state["locked"], previous_unlocked_time} do
        {true, _} -> nil
        {false, nil} -> Timex.now()
        {false, previous_unlocked_time} -> previous_unlocked_time
      end

    unlocked_delta =
      case unlocked_time do
        nil -> nil
        unlocked_time -> Timex.diff(utc_now, unlocked_time, :seconds)
      end

    state = %State{
      is_home: Geocalc.distance_between(point, @home) < 100,
      charger_plugged_in: charger_plugged_in,
      battery_level: car_state.history.battery_level,
      unlocked_time: unlocked_time,
      unlocked_delta: unlocked_delta
    }

    Logger.debug("State: #{inspect(state)}.")

    state
  end

  def process(car_state, previous_state) do
    utc_now = Timex.now()

    state = get_state(car_state, previous_state, utc_now)

    get_messages(state, previous_state, utc_now)
    |> log_messages()
    |> send_messages()

    send_state(car_state, state)

    state
  end
end
