defmodule Lens.Earnings.PDFPublicationEligibilityTest do
  use ExUnit.Case, async: true

  alias Lens.Earnings.Identity

  test "accepts explicit ordinary-report evidence without resolving a release period" do
    text = "決算短信\nコード番号 example-issuer\nExample evidence."
    assert :ok = Identity.pdf_publication_eligibility("example-issuer", text)
    assert Identity.from_text("example-issuer", text).status == :pending_confirmation
  end

  test "requires a single matching issuer code" do
    heading = "2030年3月期 決算短信"
    issuer = "コード番号 example-issuer"

    assert {:error, :issuer_mismatch} =
             Identity.pdf_publication_eligibility("other-issuer", heading <> "\n" <> issuer)

    assert {:error, :issuer_unverified} =
             Identity.pdf_publication_eligibility(
               "example-issuer",
               heading <> "\n" <> issuer <> "\nコード番号 other-issuer"
             )

    assert {:error, :issuer_unverified} =
             Identity.pdf_publication_eligibility("example-issuer", heading)
  end

  test "accepts issuer evidence across PDF titles and with no title" do
    for title <- ["決算説明資料", "決算補足資料", "「2030年3月期 決算短信」の一部訂正に関するお知らせ", ""] do
      assert :ok =
               Identity.pdf_publication_eligibility(
                 "example-issuer",
                 title <> "\nコード番号 example-issuer"
               )
    end
  end

  test "requires a configured company" do
    assert {:error, :issuer_unconfigured} =
             Identity.pdf_publication_eligibility(nil, "決算短信\nコード番号 example-issuer")
  end
end
