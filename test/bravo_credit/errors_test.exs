defmodule BravoCredit.ErrorsTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Errors

  test "invalid_params/1 returns the canonical validation error" do
    error = Errors.invalid_params(%{fields: %{country_code: ["is required"]}})

    assert error.code == "validation.invalid_params"
    assert error.http_status == 400
    assert error.source == :validation
    assert error.retryable? == false
    assert error.details == %{fields: %{country_code: ["is required"]}}
  end

  test "with_step/2 annotates the originating step" do
    error =
      Errors.unsupported_country("BR")
      |> Errors.with_step(:resolve_country_config)

    assert error.step == :resolve_country_config
    assert error.details == %{country_code: "BR"}
  end
end
