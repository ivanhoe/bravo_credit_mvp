defmodule BravoCredit.Applications.StatePolicyTest do
  use ExUnit.Case, async: true

  alias BravoCredit.Applications.StatePolicy

  test "returns country-specific transitions" do
    assert StatePolicy.available_transitions("MX", :approved) == [:cancelled]
    assert StatePolicy.available_transitions("CO", :approved) == []
    assert StatePolicy.available_transitions("CO", :in_review) == [:approved, :rejected]
  end

  test "falls back to the default transitions for unknown countries" do
    assert StatePolicy.available_transitions("CL", :approved) == [:cancelled]
  end
end
