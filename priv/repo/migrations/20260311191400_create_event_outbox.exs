defmodule BravoCredit.Repo.Migrations.CreateEventOutbox do
  use Ecto.Migration

  def change do
    create table(:event_outbox, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :aggregate_type, :string, null: false
      add :aggregate_id, :binary_id, null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false, default: fragment("'{}'::jsonb")
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec, null: false
      add :last_error_code, :string
      add :last_error_message, :text
      add :last_error_details, :map, null: false, default: fragment("'{}'::jsonb")
      add :processed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:event_outbox, [:status, :next_attempt_at], name: :idx_event_outbox_status_retry)
    create index(:event_outbox, [:aggregate_type, :aggregate_id])
  end
end
