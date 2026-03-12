defmodule BravoCredit.Webhooks.WebhookEvent do
  @moduledoc """
  Incoming or outgoing webhook event persisted for idempotency and traceability.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BravoCredit.Applications.Application

  @statuses [:received, :processing, :processed, :failed, :duplicate]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "webhook_events" do
    belongs_to :application, Application

    field :source, :string
    field :idempotency_key, :string
    field :event_type, :string
    field :payload, :map, default: %{}
    field :status, Ecto.Enum, values: @statuses, default: :received
    field :error_code, :string
    field :error_message, :string

    timestamps(type: :utc_datetime_usec)
  end

  @type status :: :received | :processing | :processed | :failed | :duplicate

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          source: String.t() | nil,
          idempotency_key: String.t() | nil,
          event_type: String.t() | nil,
          payload: map(),
          status: status() | nil,
          application_id: Ecto.UUID.t() | nil,
          error_code: String.t() | nil,
          error_message: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :source,
      :idempotency_key,
      :event_type,
      :payload,
      :status,
      :application_id,
      :error_code,
      :error_message
    ])
    |> validate_required([:source, :idempotency_key, :event_type, :status])
    |> validate_length(:source, min: 2, max: 100)
    |> validate_length(:event_type, min: 3, max: 100)
    |> foreign_key_constraint(:application_id)
    |> unique_constraint([:source, :idempotency_key],
      name: :idx_webhook_events_source_idempotency
    )
  end
end
