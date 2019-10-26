defmodule TeNerves.Estimator do
  @moduledoc """
  Estimate values for charging.
  """

  @doc """
  Estimate the charging time in minutes.
  """
  def estimate_charge_time(start, target, power, battery_max) do
    charge_required = (target - start) / 100
    total_time = battery_max / (power * 0.9)
    Timex.Duration.from_hours(charge_required * total_time)
  end

  @doc """
  Estimate the charging time of my key.
  """
  def my_charge_time(start) do
    estimate_charge_time(start, 90, 240 * 32, 80_000)
  end
end
