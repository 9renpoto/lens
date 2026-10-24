defmodule Lens.Earnings.RegisteredIdentityTest do
  use ExUnit.Case, async: true
  alias Lens.Earnings.Identity

  test "recognizes alphanumeric issuer evidence and its publication header" do
    result = Identity.from_text("SYNX", "2026年12月期 第2四半期決算短信\n2026年8月1日\nコード番号 SYNX")
    assert result.status == :identified
    assert result.fields.issuer_code == "SYNX"
    assert result.published_on == ~D[2026-08-01]

    conflict = Identity.from_text("SYNX", "2026年12月期 決算短信\nコード番号 SYNX\nコード番号 SYNX0")
    assert conflict.status == :pending_confirmation
    assert conflict.fields.issuer_code == nil
  end

  test "recognizes an issuer outside the pilot and its explicit December year end" do
    result = Identity.from_text("SYNZ", "2026年12月期 第2四半期決算短信\nコード番号 SYNZ")
    assert result.status == :identified
    assert result.release.fiscal_year_end == ~D[2026-12-31]
    assert result.release.period == "q2"
    assert result.published_on == nil
  end

  test "a changed year end is evidence rather than a fixed issuer assumption" do
    result = Identity.from_text("SYNY", "2027年8月期 第1四半期決算短信\nコード番号 SYNY")
    assert result.status == :identified
    assert result.release.fiscal_year_end == ~D[2027-08-31]
  end
end
