defmodule TeNerves.Poller do
  @moduledoc false

  @vin Application.get_env(:tenerves, :vin)

  use GenServer
  require Logger

  defmodule State do
    @enforce_keys [:token, :robotica_data, :timer, :next_time]
    defstruct [:token, :robotica_data, :timer, :next_time]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  def poll(pid) do
    Logger.debug("Got poll request")
    GenServer.call(pid, :poll, 30000)
  end

  def init(_opts) do
    state =
      %State{token: nil, robotica_data: nil, timer: nil, next_time: nil}
      |> set_timer()

    {:ok, state}
  end

  defp handle_poll(state) do
    vin = @vin
    Logger.debug("Begin poll #{vin}")

    new_state =
      with {:ok, token} <- ExTesla.check_token(state.token),
           client = ExTesla.client(token),
           {:ok, car_state} <- TeNerves.poll_tesla(client, vin) do
        robotica_data = TeNerves.Robotica.process(car_state, state.robotica_data)

        %State{
          state
          | token: token,
            robotica_data: robotica_data
        }
      else
        {:error, msg} ->
          Logger.warn("Got error #{msg}")
          state
      end

    Logger.debug("End poll")

    new_state
  end

  def get_next_time(now) do
    seconds = Timex.to_unix(now)
    units = div(seconds, 15 * 60) + 1
    Timex.from_unix(units * 15 * 60)
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

    Logger.debug("Sleeping #{milliseconds} for #{inspect(next_time)}.")
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
    earliest_time = Timex.shift(next_time, seconds: -1)
    latest_time = Timex.shift(next_time, minutes: 1)

    new_state =
      cond do
        Timex.before?(now, earliest_time) ->
          Logger.debug("Timer received too early for #{next_time}.")

          state
          |> set_timer()

        Timex.before?(now, latest_time) ->
          Logger.debug("Timer received on time for #{next_time}.")

          state
          |> handle_poll()
          |> Map.put(:next_time, nil)
          |> set_timer()

        true ->
          Logger.debug("Timer received too late for #{next_time}.")

          state
          |> Map.put(:next_time, nil)
          |> set_timer()
      end

    {:noreply, new_state}
  end
end
