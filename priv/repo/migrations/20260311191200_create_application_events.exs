defmodule BravoCredit.Repo.Migrations.CreateApplicationEvents do
  use Ecto.Migration

  def change do
    create table(:application_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :application_id, references(:applications, type: :binary_id, on_delete: :nothing),
        null: false

      add :event_type, :string, null: false
      add :actor, :string, null: false
      add :payload, :map, null: false, default: fragment("'{}'::jsonb")

      timestamps(type: :utc_datetime_usec)
    end

    create index(:application_events, [:application_id, :inserted_at],
             name: :idx_app_events_application_id_inserted_at
           )
  end
end
