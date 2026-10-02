defmodule Lens.Earnings.HTTPCheck do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @facts ~w(check_id issuer_code kind url final_url checked_at published_on status failure_reason http_status requests retryable response_headers metadata sha256 byte_size acquisition_id)a
  def facts, do: @facts

  schema "earnings_http_checks" do
    field(:check_id, :string)
    field(:issuer_code, :string)
    field(:kind, :string)
    field(:url, :string)
    field(:final_url, :string)
    field(:checked_at, :utc_datetime_usec)
    field(:published_on, :date)
    field(:status, :string)
    field(:failure_reason, :string)
    field(:http_status, :integer)
    field(:requests, :integer)
    field(:retryable, :boolean)
    field(:response_headers, :map, default: %{})
    field(:metadata, :map, default: %{})
    field(:sha256, :string)
    field(:byte_size, :integer)
    belongs_to(:acquisition, Lens.Earnings.Acquisition)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(check, attrs) do
    check
    |> cast(attrs, @facts)
    |> validate_required(~w(check_id issuer_code kind url checked_at status requests retryable)a)
    |> validate_length(:check_id, min: 1, max: 180)
    |> validate_inclusion(:issuer_code, ~w(6857 9983 8035))
    |> validate_inclusion(:kind, ~w(pdf listing))
    |> validate_inclusion(:status, ~w(success not_modified failed))
    |> validate_number(:requests, greater_than_or_equal_to: 0, less_than_or_equal_to: 4)
    |> validate_number(:http_status, greater_than_or_equal_to: 100, less_than_or_equal_to: 599)
    |> validate_length(:failure_reason, min: 1, max: 100)
    |> validate_url(:url)
    |> validate_url(:final_url)
    |> validate_change(:metadata, &bounded_json/2)
    |> validate_change(:response_headers, &bounded_json/2)
    |> validate_outcome()
    |> unique_constraint(:check_id)
    |> unique_constraint(:acquisition_id)
    |> foreign_key_constraint(:acquisition_id)
    |> check_constraint(:status, name: :earnings_http_check_outcome)
    |> check_constraint(:requests, name: :earnings_http_check_bounds)
    |> check_constraint(:acquisition_id, name: :earnings_http_check_acquisition)
    |> check_constraint(:acquisition_id, name: :earnings_http_check_acquisition_facts)
  end

  def valid_url?(value) when is_binary(value) do
    case URI.new(value) do
      {:ok, %{scheme: scheme, host: host, userinfo: nil}}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        byte_size(value) <= 4096

      _ ->
        false
    end
  end

  def valid_url?(_), do: false

  defp validate_url(changeset, field),
    do:
      validate_change(changeset, field, fn key, value ->
        if valid_url?(value),
          do: [],
          else: [{key, "must be an absolute HTTP(S) URL without credentials, within 4096 bytes"}]
      end)

  defp bounded_json(field, value) do
    case Jason.encode(value) do
      {:ok, json} when byte_size(json) <= 32_768 -> []
      _ -> [{field, "must encode as JSON within 32768 bytes"}]
    end
  end

  defp validate_outcome(changeset) do
    status = get_field(changeset, :status)
    http_status = get_field(changeset, :http_status)
    reason = get_field(changeset, :failure_reason)
    size = get_field(changeset, :byte_size)
    sha = get_field(changeset, :sha256)
    requests = get_field(changeset, :requests)
    cap = if get_field(changeset, :kind) == "listing", do: 2_097_152, else: 20_971_520

    valid =
      case status do
        "success" ->
          http_status == 200 and is_nil(reason) and is_integer(size) and size in 0..cap and
            is_binary(sha) and is_integer(requests) and requests > 0 and
            not is_nil(get_field(changeset, :final_url))

        "not_modified" ->
          http_status == 304 and is_nil(reason) and is_nil(size) and is_nil(sha) and
            is_integer(requests) and requests > 0

        "failed" ->
          is_binary(reason) and is_nil(size) and is_nil(sha)

        _ ->
          false
      end

    if valid,
      do: changeset,
      else: add_error(changeset, :status, "has inconsistent response facts")
  end
end
