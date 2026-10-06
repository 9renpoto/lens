defmodule Lens.Earnings.Source do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "earnings_sources" do
    belongs_to(:target, Lens.Analysis.Target)
    field(:listing_url, :string)
    field(:enabled, :boolean, default: true)
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:listing_url, :enabled])
    |> reject_target_attribute(attrs)
    |> reject_blank_enabled(attrs)
    |> validate_required([:target_id, :listing_url, :enabled])
    |> validate_change(:listing_url, fn :listing_url, url ->
      if listing_url?(url),
        do: [],
        else: [
          listing_url:
            "must be an absolute HTTP(S) listing URL without credentials or fragments, within 2048 bytes"
        ]
    end)
    |> unique_constraint(:listing_url, name: :earnings_sources_target_id_listing_url_index)
    |> foreign_key_constraint(:target_id)
    |> check_constraint(:listing_url, name: :earnings_source_url_length)
  end

  defp reject_target_attribute(changeset, attrs) do
    if Map.has_key?(attrs, :target_id) or Map.has_key?(attrs, "target_id"),
      do: add_error(changeset, :target_id, "is set by the route and cannot be changed"),
      else: changeset
  end

  defp reject_blank_enabled(changeset, attrs) do
    value = Map.get(attrs, :enabled, Map.get(attrs, "enabled"))

    if is_binary(value) and String.trim(value) == "",
      do: add_error(changeset, :enabled, "is invalid"),
      else: changeset
  end

  defp listing_url?(url) do
    with true <- Lens.Earnings.HTTPCheck.valid_url?(url),
         true <- byte_size(url) <= 2048,
         %{fragment: nil, path: path} <- URI.parse(url) do
      not String.ends_with?(String.downcase(URI.decode(path || "")), ".pdf") and
        not Regex.match?(~r/[\s\x00-\x1f\x7f]/u, url)
    else
      _ -> false
    end
  end
end
