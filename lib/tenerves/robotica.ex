defmodule TeNerves.Robotica do
  @moduledoc false
  require Logger

  @home Application.get_env(:tenerves, :home)

  defmodule State do
    @enforce_keys [:is_home, :charger_power]
    defstruct [:is_home, :charger_power]
  end

  defp prepend_if_true(list, cond, extra) do
    if cond, do: [extra | list], else: list
  end

  defp is_after_time(utc_now, time) do
    threshold_time =
      utc_now
      |> Timex.Timezone.convert("Australia/Melbourne")
      |> Timex.set(time: time)
      |> Timex.Timezone.convert("Etc/UTC")

    Timex.compare(utc_now, threshold_time) >= 0
  end

  defp get_messages(car_state, previous_state, state) do
    utc_now = Timex.now()
    after_threshold = is_after_time(utc_now, ~T[19:00:00])

    vehicle_state = car_state.vehicle["vehicle_state"]

    messages =
      []
      |> prepend_if_true(vehicle_state["df"] == 1, "DF is set")

    messages =
      if after_threshold do
        messages
        |> prepend_if_true(
          car_state.history.battery_level < 80 and not state.charger_power and state.is_home,
          "The Tesla is not plugged in, please plug in the Tesla"
        )
        |> prepend_if_true(not state.is_home, "The Tesla has not been returned")
      else
        messages
      end

    messages =
      if is_nil(previous_state) do
        messages
      else
        messages
        |> prepend_if_true(
          previous_state.charger_power and not state.charger_power,
          "The Tesla has been disconnected"
        )
        |> prepend_if_true(
          not previous_state.charger_power and state.charger_power,
          "The Tesla has been plugged in"
        )
        |> prepend_if_true(
          previous_state.is_home and not state.is_home,
          "The Tesla has been stolen"
        )
        |> prepend_if_true(
          not previous_state.is_home and state.is_home,
          "The Tesla has been returned"
        )
      end

    messages
  end

  defp send_messages([]), do: nil

  defp send_messages(messages) do
    action = %{
      "locations" => ["Brian", "Dining"],
      "actions" => [
        %{
          "message" => %{"text" => Enum.join(messages, "; ") <> "."}
        }
      ]
    }

    IO.inspect(action)

    case Jason.encode(action) do
      {:ok, message} ->
        client_id = TeNerves.Application.get_tortoise_client_id()
        :ok = Tortoise.publish(client_id, "/execute/", message, qos: 0)

      {:error, _msg} ->
        Logger.error("Error encoding JSON.")
    end

    nil
  end

  def process(car_state, previous_state) do
    drive_state = car_state.vehicle["drive_state"]
    charge_state = car_state.vehicle["charge_state"]

    point = %{
      latitude: drive_state["latitude"],
      longitude: drive_state["longitude"]
    }

    state = %State{
      is_home: Geocalc.distance_between(point, @home) < 100,
      charger_power: charge_state["charger_power"] == 1
    }

    IO.inspect(car_state)
    IO.inspect(previous_state)
    IO.inspect(state)

    get_messages(car_state, previous_state, state) |> send_messages()

    state
  end
end
