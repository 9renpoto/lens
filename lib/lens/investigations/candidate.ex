defmodule Lens.Investigations.Candidate do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "investigation_candidates" do
    field(:title, :string)
    field(:body, :string)
    field(:details_url, :string)
    field(:published_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def registration_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:title, :body, :details_url, :published_at])
    |> validate_required([:title, :body, :published_at])
    |> validate_publication_timezone()
    |> validate_length(:title, max: 255, count: :codepoints)
    |> validate_length(:body, max: 4000, count: :codepoints)
    |> validate_length(:details_url, max: 2048, count: :codepoints)
    |> validate_xml_text(:title)
    |> validate_xml_text(:body)
    |> validate_xml_text(:details_url)
    |> validate_change(:details_url, fn :details_url, url ->
      case URI.new(url) do
        {:ok, uri}
        when uri.scheme in ["http", "https"] and is_binary(uri.host) and
               uri.host != "" and is_nil(uri.userinfo) ->
          []

        _ ->
          [details_url: "must be an absolute HTTP(S) URL without credentials or whitespace"]
      end
    end)
  end

  defp validate_publication_timezone(changeset) do
    case changeset.params["published_at"] do
      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, _, _} -> changeset
          _ -> add_error(changeset, :published_at, "must be an ISO 8601 datetime with a timezone")
        end

      _ ->
        changeset
    end
  end

  defp validate_xml_text(changeset, field) do
    validate_change(changeset, field, fn ^field, text ->
      if Enum.all?(String.to_charlist(text), &xml_character?/1),
        do: [],
        else: [{field, "contains characters forbidden in XML 1.0"}]
    end)
  end

  defp xml_character?(c),
    do: c in [9, 10, 13] or c in 0x20..0xD7FF or c in 0xE000..0xFFFD or c in 0x10000..0x10FFFF
end
