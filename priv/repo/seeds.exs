alias BravoCredit.Accounts
alias BravoCredit.Accounts.User
alias BravoCredit.Applications.Application
alias BravoCredit.Repo

Mix.Task.run("app.start")
Logger.configure(level: :info)

users = [
  %{
    email: "admin@bravo.test",
    password_hash: String.duplicate("admin-demo-password-hash-", 3),
    role: :admin,
    country_access: ["BR", "CO", "ES", "IT", "MX", "PT"]
  },
  %{
    email: "analyst-mx@bravo.test",
    password_hash: String.duplicate("analyst-demo-password-hash-", 3),
    role: :analyst,
    country_access: ["MX"]
  },
  %{
    email: "viewer-co@bravo.test",
    password_hash: String.duplicate("viewer-demo-password-hash-", 3),
    role: :viewer,
    country_access: ["CO"]
  }
]

applications = [
  %{
    country_code: "MX",
    full_name: "Jane Doe",
    document_id: "GODE561231HDFRRN04",
    document_type: "CURP",
    amount: Decimal.new("50000.00"),
    monthly_income: Decimal.new("25000.00"),
    status: :approved,
    risk_status: :approved,
    risk_score: 735,
    banking_info: %{
      "provider" => "bank_mx",
      "provider_reference" => "seed-mx-approved",
      "credit_score" => 735,
      "total_debt" => "18000.00"
    },
    metadata: %{"seeded" => true, "label" => "mx-approved"},
    requested_at: DateTime.add(DateTime.utc_now(), -5, :day)
  },
  %{
    country_code: "MX",
    full_name: "Maria Lopez",
    document_id: "LOPM800101MDFRRN08",
    document_type: "CURP",
    amount: Decimal.new("20000.00"),
    monthly_income: Decimal.new("15000.00"),
    status: :pending,
    risk_status: :not_started,
    risk_score: nil,
    banking_info: %{},
    metadata: %{"seeded" => true, "label" => "mx-pending"},
    requested_at: DateTime.add(DateTime.utc_now(), -1, :day)
  },
  %{
    country_code: "CO",
    full_name: "Carlos Perez",
    document_id: "1234567890",
    document_type: "CC",
    amount: Decimal.new("3000000.00"),
    monthly_income: Decimal.new("1500000.00"),
    status: :in_review,
    risk_status: :manual_review,
    risk_score: 610,
    banking_info: %{
      "provider" => "bank_co",
      "provider_reference" => "seed-co-review",
      "credit_history" => "thin_file",
      "total_debt" => "520000.00"
    },
    metadata: %{"seeded" => true, "label" => "co-review"},
    requested_at: DateTime.add(DateTime.utc_now(), -3, :day)
  },
  %{
    country_code: "CO",
    full_name: "Ana Gomez",
    document_id: "1098765432",
    document_type: "CC",
    amount: Decimal.new("1000000.00"),
    monthly_income: Decimal.new("900000.00"),
    status: :rejected,
    risk_status: :rejected,
    risk_score: 420,
    banking_info: %{
      "provider" => "bank_co",
      "provider_reference" => "seed-co-rejected",
      "credit_history" => "delinquent",
      "total_debt" => "650000.00"
    },
    metadata: %{"seeded" => true, "label" => "co-rejected"},
    requested_at: DateTime.add(DateTime.utc_now(), -7, :day)
  }
]

hash_sha256 = fn value ->
  :sha256
  |> :crypto.hash(value)
  |> Base.encode16(case: :lower)
end

seeded_users =
  Enum.map(users, fn attrs ->
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert!(
      on_conflict: {:replace, [:password_hash, :role, :country_access, :updated_at]},
      conflict_target: :email,
      returning: true
    )
  end)

seeded_applications =
  Enum.map(applications, fn attrs ->
    document_hash = hash_sha256.(attrs.document_id)
    full_name_hash = hash_sha256.(attrs.full_name)

    %Application{}
    |> Application.changeset(%{
      country_code: attrs.country_code,
      full_name: attrs.full_name,
      full_name_hash: full_name_hash,
      document_id: attrs.document_id,
      document_hash: document_hash,
      document_type: attrs.document_type,
      amount: attrs.amount,
      monthly_income: attrs.monthly_income,
      status: attrs.status,
      risk_status: attrs.risk_status,
      risk_score: attrs.risk_score,
      banking_info: attrs.banking_info,
      metadata: attrs.metadata,
      requested_at: attrs.requested_at
    })
    |> Repo.insert!(
      on_conflict:
        {:replace,
         [
           :country_code,
           :full_name,
           :full_name_hash,
           :document_id,
           :document_type,
           :amount,
           :monthly_income,
           :status,
           :risk_status,
           :risk_score,
           :banking_info,
           :metadata,
           :requested_at,
           :updated_at
         ]},
      conflict_target: :document_hash,
      returning: true
    )
  end)

IO.puts("Seeded users:")

Enum.each(seeded_users, fn user ->
  IO.puts("  #{user.email} (#{user.role}) countries=#{Enum.join(user.country_access, ",")}")
end)

IO.puts("\nSeeded applications:")

Enum.each(seeded_applications, fn application ->
  IO.puts(
    "  #{application.id} #{application.country_code} #{application.status}/#{application.risk_status}"
  )
end)

IO.puts("\nDemo JWTs:")

Enum.each(seeded_users, fn user ->
  {:ok, token, _claims} = Accounts.issue_token(user)
  IO.puts("  #{user.email}")
  IO.puts("  #{token}")
end)
