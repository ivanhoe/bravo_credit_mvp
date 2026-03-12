defmodule BravoCredit.Applications.ApplicationEvent do
  @moduledoc """
  Append-only domain event stored for auditability and downstream processing.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BravoCredit.Applications.Application

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "application_events" do
    belongs_to :application, Application

    field :event_type, :string
    field :actor, :string, default: "system"
    field :payload, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          application_id: Ecto.UUID.t() | nil,
          event_type: String.t() | nil,
          actor: String.t() | nil,
          payload: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:application_id, :event_type, :actor, :payload])
    |> validate_required([:application_id, :event_type, :actor])
    |> validate_length(:event_type, min: 3, max: 100)
    |> foreign_key_constraint(:application_id)
  end
end
