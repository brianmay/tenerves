defmodule TeNerves.Electricity do
  use Timex

  def get_network_tarif_per_kwh("Consumption", l_dt) do
    {peak, shoulder, off_peak} = {13.1880, 10.1890, 3.0724}

    day_of_week = Date.day_of_week(l_dt)

    case {day_of_week, l_dt.hour} do
      {dow, hour} when dow in 1..5 and hour in 15..20 ->
        peak / 100

      {_, hour} when hour in 7..21 ->
        shoulder / 100

      {_, _} ->
        off_peak / 100
    end
  end

  def get_network_tarif_per_kwh("Controlled Load Consumption", _l_dt) do
    2.8996 / 100
  end

  def get_distribution_loss_factors_per_kwh(_l_dt) do
    1.0597
  end

  def get_green_tarif_per_kwh(_l_dt) do
    1.9 / 100
  end

  def get_market_environment_tarif_per_kwh(_l_dt) do
    2.06846258860692 / 100
  end

  def get_distribution_annual_charges(_l_dt) do
    109.00
  end

  def get_meter_annual_charges(_l_dt) do
    60.80
  end

  def get_ws_price_per_year("Consumption", l_dt) do
    get_distribution_annual_charges(l_dt) + get_meter_annual_charges(l_dt)
  end

  def get_ws_price_per_year("Controlled Load Consumption", _l_dt) do
    0
  end

  def get_retailer_price_per_kwh("Consumption", l_dt) do
    {peak, shoulder, off_peak} =
      cond do
        Date.compare(l_dt, ~D[2018-03-01]) in [:eq, :gt] -> {32.36, 28.59, 18.19}
        Date.compare(l_dt, ~D[2018-01-01]) in [:eq, :gt] -> {32.22, 28.78, 18.95}
        Date.compare(l_dt, ~D[2017-01-01]) in [:eq, :gt] -> {25.71, 25.71, 25.71}
        true -> {0, 0, 0}
      end

    day_of_week = Date.day_of_week(l_dt)

    case {day_of_week, l_dt.hour} do
      {dow, hour} when dow in 1..5 and hour in 15..20 ->
        peak / 100

      {_, hour} when hour in 7..21 ->
        shoulder / 100

      {_, _} ->
        off_peak / 100
    end
  end

  def get_retailer_price_per_kwh("Controlled Load Consumption", l_dt) do
    {peak, shoulder, off_peak} =
      cond do
        Date.compare(l_dt, ~D[2018-03-01]) in [:eq, :gt] -> {32.36, 28.59, 18.19}
        Date.compare(l_dt, ~D[2018-01-01]) in [:eq, :gt] -> {32.22, 28.78, 18.95}
        Date.compare(l_dt, ~D[2017-01-01]) in [:eq, :gt] -> {15.90, 15.90, 15.90}
        true -> {0, 0, 0}
      end

    day_of_week = Date.day_of_week(l_dt)

    case {day_of_week, l_dt.hour} do
      {dow, hour} when dow in 1..5 and hour in 15..20 ->
        peak / 100

      {_, hour} when hour in 7..21 ->
        shoulder / 100

      {_, _} ->
        off_peak / 100
    end
  end

  def get_retailer_price_per_year("Consumption", l_dt) do
    cond do
      Date.compare(l_dt, ~D[2018-03-01]) in [:eq, :gt] -> 104.19
      Date.compare(l_dt, ~D[2018-01-01]) in [:eq, :gt] -> 107.54
      Date.compare(l_dt, ~D[2017-01-01]) in [:eq, :gt] -> 107.52
      true -> 104.19
    end
  end

  def get_retailer_price_per_year("Controlled Load Consumption", _l_dt) do
    0
  end

  def get_market_price_per_kwh(date_time) do
    case TeNerves.Market.get_rates_at_time(date_time) do
      nil -> nil
      price -> price / 1000
    end
  end

  def get_total_price_per_kwh(date_time) do
    l_dt = Timezone.convert(date_time, "Australia/Melbourne")
    circuit = "Consumption"

    market_price_kwh = get_market_price_per_kwh(date_time)
    distribution_loss_factors = get_distribution_loss_factors_per_kwh(l_dt)
    network_tarif = get_network_tarif_per_kwh(circuit, l_dt)
    green_tarif = get_green_tarif_per_kwh(l_dt)
    market_environment_tarif = get_market_environment_tarif_per_kwh(l_dt)
    retailer_price_kwh = get_retailer_price_per_kwh(circuit, l_dt)

    case market_price_kwh do
      nil ->
        nil

      _ ->
        total_price_kwh =
          market_price_kwh
          |> Kernel.*(distribution_loss_factors)
          |> Kernel.+(network_tarif)
          |> Kernel.+(green_tarif)
          |> Kernel.+(market_environment_tarif)

        IO.puts(
          "#{date_time} M:#{market_price_kwh} * LOSS:#{distribution_loss_factors} + NET:#{
            network_tarif
          } + GRN:#{green_tarif} + MRKT:#{market_environment_tarif} = #{total_price_kwh} (retail:#{
            retailer_price_kwh
          })"
        )

        total_price_gst = total_price_kwh * 1.1

        total_price_gst
    end
  end

  def get_total_price_per_year(date_time) do
    l_dt = Timezone.convert(date_time, "Australia/Melbourne")
    circuit = "Consumption"

    ws_annual_charges = get_ws_price_per_year(circuit, l_dt)
    retailer_annual_charges = get_retailer_price_per_year(circuit, l_dt)

    total_price = ws_annual_charges + retailer_annual_charges
    total_price_gst = total_price * 1.1

    total_price_gst
  end

  def get_rates_for_block(date_time, duration) do
    TeNerves.Market.get_time_block(date_time, duration)
    |> Enum.map(fn date_time -> {date_time, get_total_price_per_kwh(date_time)} end)
  end

  defp average([]), do: nil

  defp average(list) do
    length = Enum.count(list)
    total = Enum.reduce(list, 0, fn price, acc -> price + acc end)
    total / length
  end

  def get_avg_for_block(date_time, duration) do
    get_rates_for_block(date_time, duration)
    |> Enum.map(fn {_date_time, price} -> price end)
    |> Enum.filter(fn price -> not is_nil(price) end)
    |> average
  end

  def get_price_start_time_table(start_date_time, latest_date_time, duration, values \\ []) do
    time_block = TeNerves.Market.get_time_block(start_date_time, duration)
    [first_time_in_block] = Enum.take(time_block, 1)
    [last_time_in_block] = Enum.take(time_block, -1)

    if Timex.compare(last_time_in_block, latest_date_time) >= 0 do
      values
    else
      new_price = get_avg_for_block(start_date_time, duration)
      new_values = [{first_time_in_block, new_price} | values]
      next_date_time = Timex.add(start_date_time, Timex.Duration.from_minutes(30))
      get_price_start_time_table(next_date_time, latest_date_time, duration, new_values)
    end
  end

  def get_min_max_price_start_time(start_date_time, latest_date_time, duration) do
    get_price_start_time_table(start_date_time, latest_date_time, duration)
    |> Enum.filter(fn {_date_time, price} -> not is_nil(price) end)
    |> Enum.min_max_by(fn {_date_time, price} -> price end)
  end
end
