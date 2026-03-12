defmodule BravoCredit.Repo.Migrations.CreateApplications do
  use Ecto.Migration

  def change do
    create table(:applications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :country_code, :string, null: false
      add :full_name, :binary, null: false
      add :full_name_hash, :string, null: false
      add :document_id, :binary, null: false
      add :document_hash, :string, null: false
      add :document_type, :string, null: false
      add :amount, :decimal, precision: 18, scale: 2, null: false
      add :monthly_income, :decimal, precision: 18, scale: 2, null: false
      add :status, :string, null: false
      add :risk_status, :string, null: false
      add :risk_score, :integer
      add :banking_info, :map, null: false, default: fragment("'{}'::jsonb")
      add :metadata, :map, null: false, default: fragment("'{}'::jsonb")
      add :requested_at, :utc_datetime_usec, null: false
      add :lock_version, :integer, null: false, default: 1

      timestamps(type: :utc_datetime_usec)
    end

    create index(:applications, [:country_code, :status], name: :idx_applications_country_status)

    create index(:applications, [:country_code, :requested_at],
             name: :idx_applications_country_requested_at
           )

    create unique_index(:applications, [:document_hash], name: :idx_applications_document_hash)

    create constraint(:applications, :applications_amount_positive, check: "amount > 0")

    create constraint(:applications, :applications_monthly_income_positive,
             check: "monthly_income > 0"
           )
  end
end
