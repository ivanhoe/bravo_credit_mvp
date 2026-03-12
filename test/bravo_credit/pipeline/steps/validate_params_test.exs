defmodule BravoCredit.Pipeline.Steps.ValidateParamsTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Pipeline.Context
  alias BravoCredit.Pipeline.Steps.ValidateParams

  test "normalizes a valid create application payload" do
    context = %Context{
      request_id: Ecto.UUID.generate(),
      actor: "public_api",
      raw_params: %{
        "country_code" => "mx",
        "full_name" => "  Jane Doe  ",
        "document_id" => " gode561231hdfrrn04 ",
        "amount" => "50000.00",
        "monthly_income" => "25000.00",
        "metadata" => %{"channel" => "web"}
      }
    }

    assert {:ok, next_context} = ValidateParams.call(context)
    assert next_context.input.country_code == "MX"
    assert next_context.input.full_name == "Jane Doe"
    assert next_context.input.document_id == "gode561231hdfrrn04"
    assert next_context.input.amount == Decimal.new("50000.00")
  end

  test "returns canonical field errors for invalid payloads" do
    context = %Context{
      request_id: Ecto.UUID.generate(),
      actor: "public_api",
      raw_params: %{
        "country_code" => "m",
        "amount" => "-1"
      }
    }

    assert {:error, error} = ValidateParams.call(context)
    assert error.code == "validation.invalid_params"
    assert error.details.fields.country_code == ["should be 2 character(s)"]
    assert error.details.fields.full_name == ["can't be blank"]
    assert error.details.fields.monthly_income == ["can't be blank"]
  end
end
