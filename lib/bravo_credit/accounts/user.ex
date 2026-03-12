defmodule BravoCredit.Accounts.User do
  @moduledoc """
  Backoffice user with role-based access and country-scoped permissions.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @roles [:admin, :analyst, :viewer]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :password_hash, :string
    field :role, Ecto.Enum, values: @roles
    field :country_access, {:array, :string}, default: []

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          email: String.t() | nil,
          password_hash: String.t() | nil,
          role: :admin | :analyst | :viewer | nil,
          country_access: [String.t()],
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password_hash, :role, :country_access])
    |> update_change(:email, &normalize_email/1)
    |> normalize_country_access()
    |> validate_required([:email, :password_hash, :role])
    |> validate_length(:email, min: 3, max: 160)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:password_hash, min: 20)
    |> validate_change(:country_access, &validate_country_access/2)
    |> unique_constraint(:email)
  end

  defp normalize_email(email), do: email |> String.trim() |> String.downcase()

  defp normalize_country_access(changeset) do
    update_change(changeset, :country_access, fn country_access ->
      country_access
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.upcase/1)
      |> Enum.uniq()
    end)
  end

  defp validate_country_access(:country_access, country_access) do
    Enum.flat_map(country_access, fn country_code ->
      cond do
        byte_size(country_code) != 2 ->
          [country_access: "must contain ISO 3166-1 alpha-2 country codes"]

        country_code != String.upcase(country_code) ->
          [country_access: "must contain uppercase country codes"]

        true ->
          []
      end
    end)
  end
end
