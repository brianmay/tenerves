defmodule TeNerves.Robotica do
  @moduledoc false
  require Logger

  def process(car_state, _robotica_data) do
    if car_state.vehicle_state["df"] == 1 do
      Logger.debug("DF")
    end
    if car_state.vehicle_state["dr"] == 1 do
      Logger.debug("DR")
    end
    if car_state.vehicle_state["fr"] == 1 do
      Logger.debug("PF")
    end
    if car_state.vehicle_state["pr"] == 1 do
      Logger.debug("PR")
    end
    if car_state.vehicle_state["ft"] == 1 do
      Logger.debug("FT")
    end
    if car_state.vehicle_state["rt"] == 1 do
      Logger.debug("RT")
    end
    if car_state.charge_state["charger_power"] == 1 do
      Logger.debug("charger_power")
    end

#    action = %{
#      "locations" => ["Brian"],
#      "actions" => [
#          %{
#              "message" => %{"text" => "Hello."}
#          }
#      ]
#    }
#
#    case Jason.encode(action) do
#      {:ok, message} ->
#        client_id = TeNerves.Application.get_tortoise_client_id()
#        :ok = Tortoise.publish(client_id, "/execute/", message, qos: 0)
#      {:error, _msg} ->
#        Logger.error("Error encoding JSON.")
#    end

    nil
  end
end
