defmodule TeNerves.Repo.Migrations.AddGeom do
  use Ecto.Migration

  def change do
    alter table("history") do
      add :position, :point
    end
    create index("history", [:position])
  end
end
