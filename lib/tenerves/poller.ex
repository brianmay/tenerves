defmodule TeNerves.Poller do
  @moduledoc false

  @vin Application.get_env(:tenerves, :vin)

  use GenServer
  require Logger

  defmodule State do
    @enforce_keys [:token, :robotica_data]
    defstruct [:token, :robotica_data]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  def poll(pid) do
    GenServer.call(pid, :poll, 30000)
  end

  def init(_opts) do
    {:ok, %State{token: nil, robotica_data: nil}}
  end

  def handle_call(:poll, _from, state) do
    vin = @vin

    new_state =
      with {:ok, token} <- ExTesla.check_token(state.token),
           client = ExTesla.client(token),
           {:ok, car_state} = TeNerves.poll_tesla(client, vin) do

        robotica_data = TeNerves.Robotica.process(car_state, state.robotica_data)
        %State{token: token, robotica_data: robotica_data}
      else
        {:error, msg} ->
          Logger.warn("Got error #{msg}")
          state
      end

    {:reply, :ok, new_state}
  end
end
