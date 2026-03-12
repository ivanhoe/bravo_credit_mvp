defmodule BravoCredit.Pipelines.EvaluateRiskTest do
  use BravoCredit.DataCase, async: true

  alias BravoCredit.Applications
  alias BravoCredit.Applications.Application, as: CreditApplication
  alias BravoCredit.Pipelines.EvaluateRisk

  test "approves a mexican application with a strong credit score" do
    application =
      create_ready_application("MX", %{
        "provider" => "bank_mx",
        "provider_reference" => "mx-rrn04",
        "credit_score" => 720,
        "total_debt" => "15000.00"
      })

    assert {:ok, context} = EvaluateRisk.call(application.id)
    assert context.application.status == :approved
    assert context.application.risk_status == :approved
    assert context.application.risk_score == 720
  end

  test "sends a mexican application to manual review for a weak credit score" do
    application =
      create_ready_application("MX", %{
        "provider" => "bank_mx",
        "provider_reference" => "mx-rrn04",
        "credit_score" => 620,
        "total_debt" => "15000.00"
      })

    assert {:ok, context} = EvaluateRisk.call(application.id)
    assert context.application.status == :in_review
    assert context.application.risk_status == :manual_review
    assert context.application.risk_score == 620
  end

  test "rejects a colombian application when debt ratio exceeds the threshold" do
    application =
      create_ready_application(
        "CO",
        %{
          "provider" => "bank_co",
          "provider_reference" => "co-1234",
          "credit_history" => "clean",
          "total_debt" => "700000.00"
        },
        %{
          "amount" => "1000000.00",
          "monthly_income" => "1500000.00"
        }
      )

    assert {:ok, context} = EvaluateRisk.call(application.id)
    assert context.application.status == :rejected
    assert context.application.risk_status == :rejected
    assert is_integer(context.application.risk_score)
  end

  defp create_ready_application(country_code, banking_info, overrides \\ %{}) do
    {:ok, application} =
      Applications.create(
        Map.merge(
          %{
            "country_code" => country_code,
            "full_name" => "Jane Doe",
            "document_id" => document_id_for(country_code),
            "amount" => "50000.00",
            "monthly_income" => "25000.00"
          },
          overrides
        ),
        "public_api"
      )

    application
    |> CreditApplication.update_changeset(%{
      banking_info: banking_info,
      status: :evaluating,
      risk_status: :provider_data_ready
    })
    |> Repo.update!()
  end

  defp document_id_for("MX"), do: "GODE561231HDFRRN04"
  defp document_id_for("CO"), do: "1234567890"
end
