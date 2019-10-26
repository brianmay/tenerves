defmodule TeNerves.Market do
  @moduledoc false

  use GenServer
  require Logger

  defmodule State do
    @enforce_keys [:rates, :timer, :next_time]
    defstruct [:rates, :timer, :next_time]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  def poll() do
    Logger.debug("TeNerves.Market: Got poll request")
    GenServer.call(TeNerves.Market, :poll, 30000)
  end

  def get_time_block(date_time, duration) do
    date_time = TeNerves.Times.round_time_up(date_time, 30 * 60)

    blocks =
      duration
      |> Timex.Duration.to_minutes()
      |> Kernel./(30)
      |> Float.ceil()
      |> trunc()

    Stream.iterate(0, &(&1 + 1))
    |> Enum.take(blocks)
    |> Enum.map(fn n -> Timex.add(date_time, Timex.Duration.from_minutes(n * 30)) end)
  end

  def get_rates_at_time(date_time) do
    date_time =
      date_time
      |> Timex.Timezone.convert("UTC")
      |> TeNerves.Times.round_time(30 * 60, 0)

    GenServer.call(TeNerves.Market, {:get_rates, date_time}, 30000)
  end

  def init(_opts) do
    timer = Process.send_after(self(), :timer, 0)

    state = %State{rates: %{}, timer: timer, next_time: DateTime.utc_now()}

    {:ok, state}
  end

  defp handle_poll(state) do
    Logger.debug("TeNerves.Market: Begin poll")

    new_state =
      case TeNerves.Aemo.get_prices() do
        {:ok, rates} ->
          Logger.debug("TeNerves.Market: Got new rates")
          %{state | rates: rates}

        {:error, msg} ->
          Logger.warn("TeNerves.Market: Got error #{msg}")
          state
      end

    Logger.debug("TeNerves.Market: End poll")
    new_state
  end

  def get_next_time(now) do
    interval = 30 * 60
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

    Logger.debug("TeNerves.Market: Sleeping #{milliseconds} for #{inspect(next_time)}.")
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

  def handle_call({:get_rates, date_time}, _from, state) do
    {:reply, Map.get(state.rates, date_time), state}
  end

  def handle_info(:timer, %State{next_time: next_time} = state) do
    now = DateTime.utc_now()
    earliest_time = next_time
    latest_time = Timex.shift(next_time, minutes: 1)

    new_state =
      cond do
        Timex.before?(now, earliest_time) ->
          Logger.debug("TeNerves.Market: Timer received too early for #{next_time}.")

          state
          |> set_timer()

        Timex.before?(now, latest_time) ->
          Logger.debug("TeNerves.Market: Timer received on time for #{next_time}.")

          state
          |> handle_poll()
          |> Map.put(:next_time, nil)
          |> set_timer()

        true ->
          Logger.debug("TeNerves.Market: Timer received too late for #{next_time}.")

          state
          |> Map.put(:next_time, nil)
          |> set_timer()
      end

    {:noreply, new_state}
  end
end
