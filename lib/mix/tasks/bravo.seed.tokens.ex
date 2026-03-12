defmodule Mix.Tasks.Bravo.Seed.Tokens do
  @shortdoc "Prints JWTs for the seeded local users"

  @moduledoc """
  Prints JWTs for the seeded local users created by `priv/repo/seeds.exs`.

      mix bravo.seed.tokens
      mix bravo.seed.tokens --env
  """

  use Mix.Task

  import Ecto.Query

  alias BravoCredit.Accounts
  alias BravoCredit.Accounts.User
  alias BravoCredit.Repo

  @emails [
    "admin@bravo.test",
    "analyst-mx@bravo.test",
    "viewer-co@bravo.test"
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Logger.configure(level: :info)

    env_format? =
      Keyword.get(OptionParser.parse!(args, strict: [env: :boolean]) |> elem(0), :env, false)

    users =
      Repo.all(from user in User, where: user.email in ^@emails, order_by: user.email)

    if users == [] do
      Mix.raise("No seeded users found. Run `mix run priv/repo/seeds.exs` first.")
    end

    Enum.each(users, fn user ->
      {:ok, token, _claims} = Accounts.issue_token(user)

      if env_format? do
        Mix.shell().info("export #{env_var_for(user.email)}=#{token}")
      else
        Mix.shell().info("#{user.email} (#{user.role})")
        Mix.shell().info(token)
        Mix.shell().info("")
      end
    end)
  end

  defp env_var_for("admin@bravo.test"), do: "BRAVO_ADMIN_TOKEN"
  defp env_var_for("analyst-mx@bravo.test"), do: "BRAVO_ANALYST_MX_TOKEN"
  defp env_var_for("viewer-co@bravo.test"), do: "BRAVO_VIEWER_CO_TOKEN"
  defp env_var_for(email), do: email |> String.upcase() |> String.replace(~r/[^A-Z0-9]+/, "_")
end
