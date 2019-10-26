defmodule TeNerves.Times do
  def round_time(date_time, interval, offset) do
    seconds = Timex.to_unix(date_time)
    units = div(seconds, interval) + offset
    Timex.from_unix(units * interval)
  end

  def round_time_up(date_time, interval) do
    seconds = Timex.to_unix(date_time)
    units = (seconds / interval) |> Float.ceil() |> trunc
    Timex.from_unix(units * interval)
  end
end
