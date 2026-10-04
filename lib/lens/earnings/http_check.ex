defmodule Lens.Earnings.HTTPCheck do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @facts ~w(check_id issuer_code kind url final_url checked_at published_on status failure_reason http_status requests retryable response_headers metadata sha256 byte_size acquisition_id)a
  @text_fields ~w(check_id issuer_code kind url final_url status failure_reason sha256)a
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
    |> validate_text_fields()
    |> validate_required(
      ~w(check_id issuer_code kind url final_url checked_at status requests retryable metadata response_headers)a
    )
    |> validate_length(:check_id, min: 1, max: 180)
    |> validate_inclusion(:issuer_code, ~w(6857 9983 8035))
    |> validate_inclusion(:kind, ~w(pdf listing))
    |> validate_inclusion(:status, ~w(success not_modified failed))
    |> validate_number(:requests, greater_than_or_equal_to: 0, less_than_or_equal_to: 4)
    |> validate_number(:http_status, greater_than_or_equal_to: 100, less_than_or_equal_to: 599)
    |> validate_length(:failure_reason, min: 1, max: 100)
    |> validate_url(:url)
    |> validate_final_url()
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
    with true <- String.valid?(value),
         :nomatch <- :binary.match(value, <<0>>),
         {:ok, %{scheme: scheme, host: host, userinfo: nil}} <- URI.new(value),
         true <- scheme in ["http", "https"] and is_binary(host) and host != "" do
      byte_size(value) <= 4096
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def valid_url?(_), do: false

  defp validate_url(changeset, field),
    do:
      validate_change(changeset, field, fn key, value ->
        if valid_url?(value),
          do: [],
          else: [{key, "must be an absolute HTTP(S) URL without credentials, within 4096 bytes"}]
      end)

  defp validate_text_fields(changeset) do
    Enum.reduce(@text_fields, changeset, fn field, acc ->
      validate_change(acc, field, fn key, value ->
        if String.valid?(value) and :binary.match(value, <<0>>) == :nomatch,
          do: [],
          else: [{key, "must be valid UTF-8 without NUL bytes"}]
      end)
    end)
  end

  defp validate_final_url(changeset) do
    denied_target? =
      get_field(changeset, :status) == "failed" and
        get_field(changeset, :failure_reason) == "url_not_allowed"

    if denied_target? do
      validate_change(changeset, :final_url, fn key, value ->
        if byte_size(value) <= 4096,
          do: [],
          else: [{key, "must be an evaluated target within 4096 bytes"}]
      end)
    else
      validate_url(changeset, :final_url)
    end
  end

  defp bounded_json(field, value) do
    with {:ok, json} <- Jason.encode(value),
         true <- byte_size(json) <= 32_768,
         {:ok, canonical_value} <- Jason.decode(json),
         true <- jsonb_safe?(canonical_value) do
      []
    else
      _ -> [{field, "must encode as JSON without NUL characters within 32768 bytes"}]
    end
  end

  defp jsonb_safe?(value) when is_binary(value), do: not String.contains?(value, <<0>>)

  defp jsonb_safe?(values) when is_list(values),
    do: Enum.all?(values, &jsonb_safe?/1)

  defp jsonb_safe?(values) when is_map(values),
    do: Enum.all?(values, fn {key, value} -> jsonb_safe?(key) and jsonb_safe?(value) end)

  defp jsonb_safe?(_value), do: true

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
            get_field(changeset, :retryable) == false and
            not is_nil(get_field(changeset, :final_url))

        "not_modified" ->
          http_status == 304 and is_nil(reason) and is_nil(size) and is_nil(sha) and
            is_integer(requests) and requests > 0 and
            get_field(changeset, :retryable) == false and
            not is_nil(get_field(changeset, :final_url))

        "failed" ->
          is_binary(reason) and is_nil(size) and is_nil(sha) and is_integer(requests) and
            get_field(changeset, :retryable) == retryable_failure?(reason, http_status) and
            valid_failure_response?(changeset, cap) and
            not is_nil(get_field(changeset, :final_url)) and
            (requests > 0 or
               (is_nil(http_status) and get_field(changeset, :response_headers) == %{}))

        _ ->
          false
      end

    if valid,
      do: changeset,
      else: add_error(changeset, :status, "has inconsistent response facts")
  end

  defp retryable_failure?("http_error", http_status) when is_integer(http_status),
    do: http_status == 429 or http_status >= 500

  defp retryable_failure?(reason, _),
    do: reason in ["timeout", "interrupted", "transport_error"]

  defp valid_failure_response?(changeset, cap) do
    reason = get_field(changeset, :failure_reason)
    status = get_field(changeset, :http_status)
    headers = get_field(changeset, :response_headers)
    started? = get_field(changeset, :requests) > 0
    no_response? = is_nil(status) and headers == %{}

    case reason do
      "invalid_options" ->
        not started? and no_response?

      reason when reason in ["url_not_allowed", "timeout", "transport_error"] ->
        no_response?

      "interrupted" ->
        started? and no_response?

      "too_large" ->
        started? and (no_response? or (status == 200 and size_header_evidence?(headers)))

      "non_pdf" ->
        started? and status == 200 and get_field(changeset, :kind) == "pdf" and
          identity_encoding?(headers) and not guaranteed_size_overflow?(headers, cap)

      "unsupported_encoding" ->
        started? and status == 200 and unsupported_encoding?(headers) and
          not guaranteed_size_overflow?(headers, cap)

      reason when reason in ["invalid_redirect", "redirect_limit"] ->
        started? and status in [301, 302, 303, 307, 308]

      "http_error" ->
        started? and is_integer(status) and status not in [200, 301, 302, 303, 304, 307, 308]

      _ ->
        false
    end
  end

  defp unsupported_encoding?(headers) do
    with {:ok, encoding} <- header_bytes(headers, "content-encoding"),
         :nomatch <- :binary.match(encoding, <<0>>) do
      if String.valid?(encoding) do
        encoding
        |> String.split(",")
        |> Enum.any?(&(String.downcase(String.trim(&1)) != "identity"))
      else
        true
      end
    else
      _ -> false
    end
  end

  defp identity_encoding?(headers) do
    with {:ok, encoding} <- header_bytes(headers, "content-encoding", "identity"),
         true <- String.valid?(encoding) do
      encoding
      |> String.split(",")
      |> Enum.all?(&(String.downcase(String.trim(&1)) == "identity"))
    else
      _ -> false
    end
  end

  defp size_header_evidence?(headers) do
    case header_size(headers) do
      {:ok, size} -> size > 1
      _ -> false
    end
  end

  defp guaranteed_size_overflow?(headers, cap) do
    case header_size(headers) do
      {:ok, size} -> size > cap
      _ -> false
    end
  end

  defp header_size(headers) do
    with {:ok, value} <- header_bytes(headers, "content-length"),
         {size, ""} <- Integer.parse(value) do
      {:ok, size}
    else
      _ -> :error
    end
  end

  defp header_bytes(headers, name, default \\ nil) do
    with {:ok, json} <- Jason.encode(headers),
         {:ok, %{} = canonical_headers} <- Jason.decode(json) do
      header_bytes(Map.get(canonical_headers, name, default))
    else
      _ -> :error
    end
  end

  defp header_bytes(value) when is_binary(value), do: {:ok, value}

  defp header_bytes(%{"encoding" => "base64", "value" => value}) when is_binary(value),
    do: Base.decode64(value)

  defp header_bytes(_), do: :error
end
