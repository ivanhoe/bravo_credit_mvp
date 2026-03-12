defmodule BravoCredit.Applications.CreateInput do
  @moduledoc """
  Normalized input used by the create application pipeline.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :country_code, :string
    field :full_name, :string
    field :document_id, :string
    field :amount, :decimal
    field :monthly_income, :decimal
    field :metadata, :map, default: %{}
  end

  @type t :: %__MODULE__{
          country_code: String.t() | nil,
          full_name: String.t() | nil,
          document_id: String.t() | nil,
          amount: Decimal.t() | nil,
          monthly_income: Decimal.t() | nil,
          metadata: map()
        }

  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) when is_map(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:country_code, :full_name, :document_id, :amount, :monthly_income, :metadata])
    |> update_change(:country_code, fn value -> normalize_string(value, &String.upcase/1) end)
    |> update_change(:full_name, &normalize_string/1)
    |> update_change(:document_id, &normalize_string/1)
    |> validate_required([:country_code, :full_name, :document_id, :amount, :monthly_income])
    |> validate_length(:country_code, is: 2)
    |> validate_length(:full_name, min: 3, max: 255)
    |> validate_length(:document_id, min: 4, max: 32)
    |> validate_number(:amount, greater_than: 0)
    |> validate_number(:monthly_income, greater_than: 0)
    |> validate_change(:metadata, fn :metadata, value ->
      if is_map(value), do: [], else: [metadata: "must be a map"]
    end)
  end

  defp normalize_string(value), do: normalize_string(value, &Function.identity/1)

  defp normalize_string(value, formatter) when is_binary(value) do
    value
    |> String.trim()
    |> formatter.()
  end
end
