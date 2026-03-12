defmodule BravoCredit.Outbox.Event do
  @moduledoc """
  Persisted outbox event used to dispatch asynchronous side effects safely.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses [:pending, :processing, :processed, :failed]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "event_outbox" do
    field :aggregate_type, :string
    field :aggregate_id, :binary_id
    field :event_type, :string
    field :payload, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :attempts, :integer, default: 0
    field :next_attempt_at, :utc_datetime_usec
    field :last_error_code, :string
    field :last_error_message, :string
    field :last_error_details, :map, default: %{}
    field :processed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @type status :: :pending | :processing | :processed | :failed

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          aggregate_type: String.t() | nil,
          aggregate_id: Ecto.UUID.t() | nil,
          event_type: String.t() | nil,
          payload: map(),
          status: status() | nil,
          attempts: integer() | nil,
          next_attempt_at: DateTime.t() | nil,
          last_error_code: String.t() | nil,
          last_error_message: String.t() | nil,
          last_error_details: map(),
          processed_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :aggregate_type,
      :aggregate_id,
      :event_type,
      :payload,
      :status,
      :attempts,
      :next_attempt_at,
      :last_error_code,
      :last_error_message,
      :last_error_details,
      :processed_at
    ])
    |> ensure_next_attempt_at()
    |> validate_required([
      :aggregate_type,
      :aggregate_id,
      :event_type,
      :status,
      :attempts,
      :next_attempt_at
    ])
    |> validate_length(:aggregate_type, min: 3, max: 100)
    |> validate_length(:event_type, min: 3, max: 100)
    |> validate_number(:attempts, greater_than_or_equal_to: 0)
  end

  defp ensure_next_attempt_at(changeset) do
    case get_field(changeset, :next_attempt_at) do
      nil -> put_change(changeset, :next_attempt_at, DateTime.utc_now())
      _next_attempt_at -> changeset
    end
  end
end
