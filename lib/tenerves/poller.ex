defmodule TeNerves.Poller do
  @moduledoc false

  use GenServer
  require Logger

  defmodule State do
    @enforce_keys [:token, :vehicle, :robotica_data, :timer, :next_time]
    defstruct [:token, :vehicle, :robotica_data, :timer, :next_time]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  def poll(pid) do
    Logger.debug("TeNerves.Poller: Got poll request")
    GenServer.call(pid, :poll, 30000)
  end

  def init(_opts) do
    state =
      %State{token: nil, vehicle: nil, robotica_data: nil, timer: nil, next_time: nil}
      |> set_timer()

    {:ok, state}
  end

  defp get_vehicle(nil, vin, token) do
    TeNerves.get_vehicle_by_vin(token, vin)
  end

  defp get_vehicle(cached_vehicle, _vin, _token) do
    {:ok, cached_vehicle}
  end

  defp handle_poll(state) do
    vin = Application.get_env(:tenerves, :vin)
    Logger.debug("TeNerves.Poller: Begin poll #{vin}")

    new_state =
      with {:ok, token} <- TeNerves.get_token(state.token),
           {:ok, token} <- ExTesla.check_token(token),
           :ok <- TeNerves.save_token(token),
           {:ok, vehicle} <- get_vehicle(state.vehicle, vin, token),
           {:ok, car_state} <- TeNerves.poll_tesla(token, vehicle) do
        robotica_data = TeNerves.Robotica.process(car_state, state.robotica_data)

        %State{
          state
          | token: token,
            vehicle: vehicle,
            robotica_data: robotica_data
        }
      else
        {:error, msg} ->
          Logger.warn("TeNerves.Poller: Got error #{msg}")
          state
      end

    Logger.debug("TeNerves.Poller: End poll")

    new_state
  end

  def get_next_time(now) do
    interval = 60
    TeNerves.Times.round_time(now, interval, 1)
  end

  defp maximum(v, max) when v > max, do: max
  defp maximum(v, _max), do: v

  defp minimum(v, max) when v < max, do: max
  defp minimum(v, _max), do: v

  defp set_timer(%State{next_time: next_time} = state) do
    now = DateTime.utc_now()

    next_time =
      case next_time do
        nil -> get_next_time(now)
        next_time -> next_time
      end

    milliseconds = Timex.diff(next_time, now, :milliseconds)
    milliseconds = maximum(milliseconds, 60 * 1000)
    milliseconds = minimum(milliseconds, 0)

    Logger.debug("TeNerves.Poller: Sleeping #{milliseconds} for #{inspect(next_time)}.")
    timer = Process.send_after(self(), :timer, milliseconds)

    %State{
      state
      | timer: timer,
        next_time: next_time
    }
  end

  def handle_call(:poll, _from, state) do
    new_state = handle_poll(state)
    {:reply, :ok, new_state}
  end

  def handle_info(:timer, %State{next_time: next_time} = state) do
    now = DateTime.utc_now()
    earliest_time = next_time
    latest_time = Timex.shift(next_time, seconds: 10)

    new_state =
      cond do
        Timex.before?(now, earliest_time) ->
          Logger.debug("TeNerves.Poller: Timer received too early for #{next_time}.")

          state
          |> set_timer()

        Timex.before?(now, latest_time) ->
          Logger.debug("TeNerves.Poller: Timer received on time for #{next_time}.")

          state
          |> handle_poll()
          |> Map.put(:next_time, nil)
          |> set_timer()

        true ->
          Logger.debug("TeNerves.Poller: Timer received too late for #{next_time}.")

          state
          |> Map.put(:next_time, nil)
          |> set_timer()
      end

    {:noreply, new_state}
  end

  def handle_info({:mojito_response, _, _}, %State{} = state) do
    Logger.error("Got late HTTP response")
    {:noreply, state}
  end
end
