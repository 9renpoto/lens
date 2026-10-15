defmodule Lens.Earnings.RegisteredIdentityTest do
  use ExUnit.Case, async: true
  alias Lens.Earnings.Identity

  test "recognizes an issuer outside the pilot and its explicit December year end" do
    result = Identity.from_text("1234", "2026年12月期 第2四半期決算短信\nコード番号 1234")
    assert result.status == :identified
    assert result.release.fiscal_year_end == ~D[2026-12-31]
    assert result.release.period == "q2"
    assert result.published_on == nil
    assert Identity.select_initial([result]) == {:ok, result}
  end

  test "a changed year end is evidence rather than a fixed issuer assumption" do
    result = Identity.from_text("6857", "2027年8月期 第1四半期決算短信\nコード番号 6857")
    assert result.status == :identified
    assert result.release.fiscal_year_end == ~D[2027-08-31]
  end
end
