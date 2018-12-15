defmodule TeNerves.Robotica do
  @moduledoc false
  require Logger

  @home Application.get_env(:tenerves, :home)

  defmodule State do
    @enforce_keys [:is_home, :charger_plugged_in, :battery_level, :unlocked_time]
    defstruct [:is_home, :charger_plugged_in, :battery_level, :unlocked_time]
  end

  defp is_after_time(utc_now, time) do
    threshold_time =
      utc_now
      |> Timex.Timezone.convert("Australia/Melbourne")
      |> Timex.set(time: time)
      |> Timex.Timezone.convert("Etc/UTC")

    Timex.compare(utc_now, threshold_time) >= 0
  end

  defp get_messages(state, previous_state) do
    utc_now = Timex.now()
    after_threshold = is_after_time(utc_now, ~T[20:00:00])

    day_of_week =
      utc_now
      |> Timex.Timezone.convert("Australia/Melbourne")
      |> Date.day_of_week()

    unlocked_delta =
      case state.unlocked_time do
        nil -> nil
        unlocked_time -> Timex.diff(utc_now, unlocked_time, :seconds)
      end

    rules = [
      {
        not is_nil(unlocked_delta) and unlocked_delta >= 10,
        "The Tesla has been unlocked for more then 10 minutes."
      },
      {
        after_threshold and state.battery_level < 80 and not state.charger_plugged_in and
          state.is_home and day_of_week not in [4, 7],
        "The Tesla is not plugged in, please plug in the Tesla."
      },
      {
        is_after_time(utc_now, ~T[21:30:00]) and state.battery_level < 80 and
          not state.charger_plugged_in and state.is_home and day_of_week in [4],
        "The Tesla is not plugged in, please plug in the Tesla."
      },
      {
        is_after_time(utc_now, ~T[21:00:00]) and state.battery_level < 80 and
          not state.charger_plugged_in and state.is_home and day_of_week in [7],
        "The Tesla is not plugged in, please plug in the Tesla."
      },
      {
        not is_nil(previous_state) and previous_state.charger_plugged_in and
          not state.charger_plugged_in,
        "The Tesla has been disconnected."
      },
      {
        not is_nil(previous_state) and not previous_state.charger_plugged_in and
          state.charger_plugged_in,
        "The Tesla has been plugged in."
      },
      {
        not is_nil(previous_state) and previous_state.is_home and not state.is_home,
        "The Tesla has been stolen."
      },
      {
        not is_nil(previous_state) and not previous_state.is_home and state.is_home,
        "The Tesla has been returned."
      }
    ]

    rules
    |> Enum.filter(fn {cond, _} -> cond end)
    |> Enum.map(fn {_, msg} -> msg end)
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
      "actions" => [
        %{
          "message" => %{"text" => Enum.join(messages, " ")}
        }
      ]
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

  def get_state(car_state, previous_state) do
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

    state = %State{
      is_home: Geocalc.distance_between(point, @home) < 100,
      charger_plugged_in: charger_plugged_in,
      battery_level: car_state.history.battery_level,
      unlocked_time: unlocked_time
    }

    Logger.debug("State: #{inspect(state)}.")

    state
  end

  def process(car_state, previous_state) do
    state = get_state(car_state, previous_state)

    get_messages(state, previous_state)
    |> log_messages()
    |> send_messages()

    state
  end
end
