defmodule TeNerves.Repo.Migrations.PopulatePosition do
  use Ecto.Migration
  import Ecto.Query

  def up do
    from(p in "history",
      update: [set: [position: ^%Geo.Point{coordinates: {p.longitude, p.latitude}, srid: 4326}]]
    )
    |> TeNerves.Repo.update_all([])
  end
end
