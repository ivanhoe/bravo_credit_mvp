defmodule BravoCredit.Repo.Migrations.CreateWebhookEvents do
  use Ecto.Migration

  def change do
    create table(:webhook_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source, :string, null: false
      add :idempotency_key, :string, null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false, default: fragment("'{}'::jsonb")
      add :status, :string, null: false
      add :error_code, :string
      add :error_message, :text

      add :application_id, references(:applications, type: :binary_id, on_delete: :nothing)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:webhook_events, [:source, :idempotency_key],
             name: :idx_webhook_events_source_idempotency
           )

    create index(:webhook_events, [:application_id])
  end
end
