defmodule TeNerves.Robotica do
  @moduledoc false
  require Logger

  @home Application.get_env(:tenerves, :home)

  defmodule State do
    @enforce_keys [:is_home, :charger_plugged_in]
    defstruct [:is_home, :charger_plugged_in]
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

    rules = [
      {
        vehicle_state["df"] > 0,
        "The Tesla driver front door is open."
      },
      {
        vehicle_state["dr"] > 0,
        "The Tesla driver rear door is open."
      },
      {
        vehicle_state["pf"] > 0,
        "The Tesla passenger front door is open."
      },
      {
        vehicle_state["pr"] > 0,
        "The Tesla passenger rear door is open."
      },
      {
        vehicle_state["ft"] > 0,
        "The Tesla front trunk is open."
      },
      {
        vehicle_state["rt"] > 0,
        "The Tesla rear trunk is open."
      },
      {
        not vehicle_state["locked"],
        "The Tesla is unlocked."
      },
      {
         after_threshold and car_state.history.battery_level < 80 and not state.charger_plugged_in and state.is_home,
        "The Tesla is not plugged in, please plug in the Tesla."
      },
      {
        after_threshold and not state.is_home,
        "The Tesla has not returned, it might be lost - please help the Tesla find its way home."
      },
      {
        not is_nil(previous_state) and previous_state.charger_plugged_in and not state.charger_plugged_in,
        "The Tesla has been disconnected."
      },
      {
        not is_nil(previous_state) and not previous_state.charger_plugged_in and state.charger_plugged_in,
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

    charger_plugged_in = case charge_state["charging_state"] do
      nil -> previous_state.charger_plugged_in
      "Disconnected" -> false
      _ -> true
    end

    state = %State{
      is_home: Geocalc.distance_between(point, @home) < 100,
      charger_plugged_in: charger_plugged_in
    }

    IO.inspect(car_state)
    IO.inspect(previous_state)
    IO.inspect(state)

    get_messages(car_state, previous_state, state) |> send_messages()

    state
  end
end
