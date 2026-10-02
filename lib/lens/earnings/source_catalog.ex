defmodule Lens.Earnings.SourceCatalog do
  @moduledoc "Fixed pilot sources. Unresolved acquisition conditions keep every route inactive."

  @sources [
    %{
      issuer_code: "6857",
      issuer_name: "Advantest",
      listing_url: "https://www.advantest.com/ja/investors/ir-library/result/",
      terms_url: "https://www.advantest.com/ja/legal/",
      document_path_prefix: "/document/ja/investors/ir-library/result/",
      enabled: false,
      disabled_reason: :acquisition_conditions_unresolved
    },
    %{
      issuer_code: "9983",
      issuer_name: "Fast Retailing",
      listing_url: "https://www.fastretailing.com/jp/ir/library/tanshin.html",
      terms_url: "https://www.fastretailing.com/jp/disclaimer/",
      document_path_prefix: "/jp/ir/library/pdf/",
      enabled: false,
      disabled_reason: :acquisition_conditions_unresolved
    },
    %{
      issuer_code: "8035",
      issuer_name: "Tokyo Electron",
      listing_url: "https://www.tel.co.jp/ir/calendar/",
      terms_url: "https://www.tel.co.jp/copyright/index.html",
      document_path_prefix: "/ir/library/report/",
      enabled: false,
      disabled_reason: :acquisition_conditions_unresolved
    }
  ]

  def all, do: @sources

  def fetch(issuer_code) do
    case Enum.find(@sources, &(&1.issuer_code == issuer_code)) do
      nil -> {:error, :unsupported_issuer}
      source -> {:ok, source}
    end
  end

  @doc "Check a discovered URL against the reviewed document route; this does not enable acquisition."
  def document_url_allowed?(issuer_code, url) when is_binary(url) do
    with {:ok, source} <- fetch(issuer_code),
         true <- String.valid?(url),
         {:ok, %{scheme: "https", port: 443, userinfo: nil, host: host, path: path}} <-
           URI.new(url),
         true <- is_binary(host) and is_binary(path) do
      String.downcase(host) == URI.parse(source.listing_url).host and
        String.starts_with?(path, source.document_path_prefix) and
        reviewed_path?(path) and
        String.ends_with?(String.downcase(path), ".pdf")
    else
      _ -> false
    end
  end

  def document_url_allowed?(_, _), do: false

  defp reviewed_path?(path) do
    decoded = URI.decode(path)

    not String.contains?(decoded, "\\") and
      not Enum.any?(String.split(decoded, "/"), &(&1 in [".", ".."]))
  end
end
