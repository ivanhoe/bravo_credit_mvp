defmodule BravoCredit.Rules.EngineTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Countries.Registry
  alias BravoCredit.Rules.Engine

  test "MX initial rules accept a valid amount to income ratio" do
    country_config = Registry.get!("MX")

    assert :ok =
             Engine.evaluate(country_config, :initial, %{
               amount: Decimal.new("80000"),
               monthly_income: Decimal.new("25000")
             })
  end

  test "MX initial rules reject an excessive amount to income ratio" do
    country_config = Registry.get!("MX")

    assert {:error, error} =
             Engine.evaluate(country_config, :initial, %{
               amount: Decimal.new("150000"),
               monthly_income: Decimal.new("20000")
             })

    assert error.code == "rules.initial_rejected"
    assert error.details.rule_id == "amount_income_ratio"
  end

  test "CO initial rules reject income below threshold" do
    country_config = Registry.get!("CO")

    assert {:error, error} =
             Engine.evaluate(country_config, :initial, %{
               amount: Decimal.new("1000000"),
               monthly_income: Decimal.new("1000000")
             })

    assert error.code == "rules.initial_rejected"
    assert error.details.rule_id == "min_income"
  end

  test "CO provider rules accept a healthy debt ratio" do
    country_config = Registry.get!("CO")

    assert :ok =
             Engine.evaluate(
               country_config,
               :provider,
               %{monthly_income: Decimal.new("2000000")},
               %{total_debt: Decimal.new("500000")}
             )
  end

  test "CO provider rules reject a high debt ratio" do
    country_config = Registry.get!("CO")

    assert {:error, error} =
             Engine.evaluate(
               country_config,
               :provider,
               %{monthly_income: Decimal.new("1000000")},
               %{total_debt: Decimal.new("700000")}
             )

    assert error.code == "rules.initial_rejected"
    assert error.details.rule_id == "debt_income_ratio"
    assert error.details.evaluation_phase == :provider
  end
end
