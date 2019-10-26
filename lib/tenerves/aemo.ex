defmodule TeNerves.Aemo do
  def parse_time(str_time) do
    str_time
    |> NaiveDateTime.from_iso8601!()
    |> Timex.to_datetime("+10")
    |> Timex.Timezone.convert("UTC")
  end

  def get_prices do
    url = "https://aemo.com.au/aemo/apps/api/report/5MIN"

    params = %{
      "timeScale" => ["30MIN"]
    }

    params_encoded = Jason.encode!(params)
    headers = [{"Content-Type", "application/json"}]

    case HTTPoison.post(url, params_encoded, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        data =
          body
          |> Jason.decode!()
          |> Map.get("5MIN", [])
          |> Enum.filter(fn entry -> entry["REGION"] == "VIC1" end)
          |> Enum.map(fn entry ->
            time = parse_time(entry["SETTLEMENTDATE"])
            {time, entry["RRP"]}
          end)
          |> Enum.into(%{})

        {:ok, data}

      {:ok, response} ->
        {:error, "We got an unexpected HTTP response: #{inspect(response)}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Error connection to HTTP server: #{inspect(reason)}"}
    end
  end
end
