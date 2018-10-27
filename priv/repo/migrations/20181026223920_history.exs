defmodule TeNerves.Repo.Migrations.History do
  use Ecto.Migration

  def up do
    create table("history") do
      add(:vin, :string, size: 20, null: false)
      add(:date_time, :utc_datetime, null: false)
      add(:odometer, :decimal, null: false)
      add(:charge_energy_added, :decimal, null: false)
      add(:time_to_full_charge, :decimal, null: false)
      add(:battery_level, :integer, null: false)
      add(:est_battery_range, :decimal, null: false)
      add(:ideal_battery_range, :decimal, null: false)
      add(:battery_range, :decimal, null: false)
      add(:outside_temp, :decimal, null: true)
      add(:inside_temp, :decimal, null: true)
      add(:heading, :integer, null: false)
      add(:latitude, :float, null: false)
      add(:longitude, :float, null: false)
      add(:speed, :decimal, null: true)
      add(:delta_time, :integer, null: true)
      add(:delta_odometer, :decimal, null: true)
      add(:delta_charge_energy_added, :decimal, null: true)
      add(:battery_charge_time, :decimal, null: false)
      timestamps()
    end
    create(unique_index("history", [:vin, :date_time]))
  end

  def down do
    drop(table("history"))
  end
end
