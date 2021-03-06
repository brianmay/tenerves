defmodule TeNerves.Robotica do
  @moduledoc false
  require Logger

  @home Application.get_env(:tenerves, :home)

  defmodule State do
    @enforce_keys [
      :distance_from_home,
      :charger_plugged_in,
      :battery_level,
      :unlocked_time,
      :unlocked_delta,
      :next_warning_time,
      :warning_ok
    ]
    @derive Jason.Encoder
    defstruct [
      :distance_from_home,
      :charger_plugged_in,
      :battery_level,
      :unlocked_time,
      :unlocked_delta,
      :next_warning_time,
      :warning_ok
    ]
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
    warning_ok = state.warning_ok

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

    was_at_home =
      cond do
        is_nil(previous_state) -> nil
        true -> previous_state.distance_from_home < 100
      end

    now_at_home = state.distance_from_home < 100

    begin_charge_time =
      cond do
        day_of_week == 4 -> ~T[21:30:00]
        day_of_week == 7 -> ~T[21:00:00]
        true -> ~T[20:00:00]
      end

    rules = [
      {
        not is_nil(was_at_home) and was_at_home and not now_at_home,
        fn -> "The Tesla has left home." end
      },
      {
        not is_nil(was_at_home) and not was_at_home and now_at_home,
        fn -> "The Tesla has returned home." end
      },
      {
        not is_nil(unlocked_delta) and unlocked_delta >= 9 * 60 and warning_ok,
        fn -> "The Tesla has been unlocked for #{round(unlocked_delta / 60)} minutes." end
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
        is_after_time(utc_now, begin_charge_time) and state.battery_level < 80 and
          not state.charger_plugged_in and now_at_home and warning_ok,
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

  defp send_state(car_state, state) do
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

  defp get_state(car_state, previous_state, utc_now) do
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
        {nil, state} -> state.charger_plugged_in
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

    {next_warning_time, warning_ok} =
      cond do
        is_nil(previous_state) ->
          {TeNerves.Times.round_time(utc_now, 10 * 60, 1), true}

        Timex.before?(utc_now, previous_state.next_warning_time) ->
          {previous_state.next_warning_time, false}

        true ->
          {TeNerves.Times.round_time(utc_now, 10 * 60, 1), true}
      end

    state = %State{
      distance_from_home: Geocalc.distance_between(point, @home),
      charger_plugged_in: charger_plugged_in,
      battery_level: car_state.history.battery_level,
      unlocked_time: unlocked_time,
      unlocked_delta: unlocked_delta,
      next_warning_time: next_warning_time,
      warning_ok: warning_ok
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
