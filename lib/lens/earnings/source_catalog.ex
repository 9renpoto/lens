defmodule Lens.Earnings.SourceCatalog do
  @moduledoc "Registered listing sources with current issuer information from analysis targets."

  import Ecto.Query
  alias Lens.Analysis.Target
  alias Lens.Earnings.Source
  alias Lens.Repo

  def all(opts \\ []) do
    query =
      from(s in Source,
        join: t in Target,
        on: t.id == s.target_id,
        order_by: [asc: t.security_code, asc: s.inserted_at, asc: s.id],
        select: %{
          id: s.id,
          target_id: s.target_id,
          issuer_code: t.security_code,
          issuer_name: t.display_name,
          listing_url: s.listing_url,
          enabled: s.enabled
        }
      )

    query =
      if Keyword.get(opts, :enabled_only, false),
        do: from([s, _t] in query, where: s.enabled == true),
        else: query

    Repo.all(query)
  end

  def for_issuer(issuer_code), do: Enum.filter(all(), &(&1.issuer_code == issuer_code))

  def fetch(issuer_code) do
    case for_issuer(issuer_code) do
      [] -> {:error, :unsupported_issuer}
      [source] -> {:ok, source}
      _ -> {:error, :multiple_sources}
    end
  end
end
