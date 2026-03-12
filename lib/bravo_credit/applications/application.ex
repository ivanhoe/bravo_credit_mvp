defmodule BravoCredit.Applications.Application do
  @moduledoc """
  Credit application persisted as the system's main aggregate root.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__
  alias BravoCredit.Encrypted

  @statuses [
    :pending,
    :provider_processing,
    :evaluating,
    :approved,
    :rejected,
    :in_review,
    :cancelled
  ]
  @risk_statuses [:not_started, :processing, :approved, :rejected, :manual_review]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "applications" do
    field :country_code, :string
    field :full_name, Encrypted.Binary
    field :full_name_hash, :string
    field :document_id, Encrypted.Binary
    field :document_hash, :string
    field :document_type, :string
    field :amount, :decimal
    field :monthly_income, :decimal
    field :status, Ecto.Enum, values: @statuses
    field :risk_status, Ecto.Enum, values: @risk_statuses
    field :risk_score, :integer
    field :banking_info, :map, default: %{}
    field :metadata, :map, default: %{}
    field :requested_at, :utc_datetime_usec
    field :lock_version, :integer, default: 1

    timestamps(type: :utc_datetime_usec)
  end

  @type status ::
          :pending
          | :provider_processing
          | :evaluating
          | :approved
          | :rejected
          | :in_review
          | :cancelled

  @type risk_status :: :not_started | :processing | :approved | :rejected | :manual_review

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          country_code: String.t() | nil,
          full_name: String.t() | nil,
          full_name_hash: String.t() | nil,
          document_id: String.t() | nil,
          document_hash: String.t() | nil,
          document_type: String.t() | nil,
          amount: Decimal.t() | nil,
          monthly_income: Decimal.t() | nil,
          status: status() | nil,
          risk_status: risk_status() | nil,
          risk_score: integer() | nil,
          banking_info: map(),
          metadata: map(),
          requested_at: DateTime.t() | nil,
          lock_version: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(application, attrs) do
    application
    |> cast(attrs, [
      :country_code,
      :full_name,
      :full_name_hash,
      :document_id,
      :document_hash,
      :document_type,
      :amount,
      :monthly_income,
      :status,
      :risk_status,
      :risk_score,
      :banking_info,
      :metadata,
      :requested_at,
      :lock_version
    ])
    |> update_change(:country_code, &normalize_country_code/1)
    |> ensure_requested_at()
    |> validate_required([
      :country_code,
      :full_name,
      :full_name_hash,
      :document_id,
      :document_hash,
      :document_type,
      :amount,
      :monthly_income,
      :status,
      :risk_status,
      :requested_at
    ])
    |> validate_length(:country_code, is: 2)
    |> validate_length(:document_type, min: 2, max: 20)
    |> validate_number(:amount, greater_than: 0)
    |> validate_number(:monthly_income, greater_than: 0)
    |> validate_number(:risk_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
    |> unique_constraint(:document_hash, name: :idx_applications_document_hash)
  end

  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(%Application{} = application, attrs) do
    application
    |> changeset(attrs)
    |> optimistic_lock(:lock_version)
  end

  defp normalize_country_code(country_code), do: country_code |> String.trim() |> String.upcase()

  defp ensure_requested_at(changeset) do
    case get_field(changeset, :requested_at) do
      nil -> put_change(changeset, :requested_at, DateTime.utc_now())
      _requested_at -> changeset
    end
  end
end
