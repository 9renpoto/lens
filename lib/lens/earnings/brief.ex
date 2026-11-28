defmodule Lens.Earnings.Brief do
  @moduledoc "Validates and renders a local earnings brief from one cited disclosure record."

  @enforce_keys [:excerpt, :resource, :activity, :action, :status, :source_locator]
  defstruct [:excerpt, :resource, :activity, :action, :status, :source_locator]

  @type t :: %__MODULE__{
          excerpt: String.t(),
          resource: String.t(),
          activity: String.t(),
          action: String.t(),
          status: String.t(),
          source_locator: String.t()
        }

  @type error_reason ::
          :invalid_record
          | :invalid_json
          | {:file_read, String.t(), File.posix()}
          | {:unknown_fields, [String.t()]}
          | {:missing_field, String.t()}
          | {:invalid_resource, term()}
          | {:invalid_status, term()}

  @required_fields ~w(excerpt resource activity action status source_locator)
  @resources %{"people" => "人", "capital" => "資金", "equipment" => "設備"}
  @statuses %{"actual" => "実施済み", "planned" => "計画"}
  @directions %{"increase" => "需要増加", "decrease" => "需要減少"}

  @spec load_file(String.t()) :: {:ok, t()} | {:error, error_reason()}
  def load_file(path) when is_binary(path) do
    with {:ok, bytes} <- read_file(path),
         {:ok, decoded} <- decode_json(bytes) do
      new(decoded)
    end
  end

  @spec new(term()) :: {:ok, t()} | {:error, error_reason()}
  def new(attrs) when is_map(attrs) do
    with :ok <- reject_unknown_fields(attrs),
         :ok <- require_non_empty_strings(attrs),
         :ok <- validate_resource(attrs["resource"]),
         :ok <- validate_status(attrs["status"]) do
      {:ok,
       %__MODULE__{
         excerpt: attrs["excerpt"],
         resource: attrs["resource"],
         activity: attrs["activity"],
         action: attrs["action"],
         status: attrs["status"],
         source_locator: attrs["source_locator"]
       }}
    end
  end

  def new(_), do: {:error, :invalid_record}

  @spec render_facts(t()) :: String.t()
  def render_facts(%__MODULE__{} = brief) do
    quoted_excerpt =
      brief.excerpt
      |> String.split(~r/\r?\n/)
      |> Enum.map_join("\n", &"> #{&1}")

    """
    ## 開示ファクト

    - 資源: #{Map.fetch!(@resources, brief.resource)} (#{brief.resource})
    - 事業活動: #{brief.activity}
    - 動作: #{brief.action}
    - 状態: #{Map.fetch!(@statuses, brief.status)} (#{brief.status})
    - 出典: #{brief.source_locator}

    #{quoted_excerpt}
    """
    |> String.trim_trailing()
  end

  @spec render(
          t(),
          {:ok, Lens.Earnings.Brief.Hypothesis.t()}
          | {:error, Lens.Earnings.Brief.Hypothesis.error_reason()}
        ) ::
          String.t()
  def render(%__MODULE__{} = brief, {:ok, %Lens.Earnings.Brief.Hypothesis{} = hypothesis}) do
    next_step_section =
      case hypothesis.next_step do
        nil ->
          ""

        step ->
          """


          ## 任意の次の一歩

          - #{step}
          """
          |> String.trim_trailing()
      end

    """
    #{render_facts(brief)}

    ## 仕事の需要仮説（推測）

    - 根拠出典: #{brief.source_locator}
    - 変化しうる仕事: #{hypothesis.work_type}
    - 見込み方向: #{Map.fetch!(@directions, hypothesis.demand_direction)} (#{hypothesis.demand_direction})
    - 理由: #{hypothesis.reason}

    ## 一次情報での確認方法

    - #{hypothesis.verification_step}#{next_step_section}
    """
    |> String.trim_trailing()
  end

  def render(%__MODULE__{} = brief, {:error, reason}) do
    """
    #{render_facts(brief)}

    ## 仕事の需要仮説（推測）

    - 生成失敗: #{Lens.Earnings.Brief.Hypothesis.format_error(reason)}
    """
    |> String.trim_trailing()
  end

  @spec format_error(error_reason()) :: String.t()
  def format_error({:file_read, path, reason}),
    do: "Could not read input file #{path}: #{:file.format_error(reason)}"

  def format_error(:invalid_json),
    do: "Invalid JSON input: provide a single JSON object matching the earnings brief schema."

  def format_error(:invalid_record),
    do: "Invalid record: expected a JSON object with keys #{Enum.join(@required_fields, ", ")}."

  def format_error({:unknown_fields, fields}),
    do: "Unexpected field(s): #{Enum.join(fields, ", ")}."

  def format_error({:missing_field, field}),
    do: "Missing or empty required field: #{field}."

  def format_error({:invalid_resource, value}),
    do: "Invalid resource #{inspect(value)}: expected one of people, capital, equipment."

  def format_error({:invalid_status, value}),
    do: "Invalid status #{inspect(value)}: expected one of actual, planned."

  defp read_file(path) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, {:file_read, path, reason}}
    end
  end

  defp decode_json(bytes) do
    case Jason.decode(bytes) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp reject_unknown_fields(attrs) do
    unknown =
      attrs
      |> Map.keys()
      |> Enum.reject(&(&1 in @required_fields))
      |> Enum.map(&to_string/1)
      |> Enum.sort()

    case unknown do
      [] -> :ok
      fields -> {:error, {:unknown_fields, fields}}
    end
  end

  defp require_non_empty_strings(attrs) do
    Enum.reduce_while(@required_fields, :ok, fn field, :ok ->
      case Map.get(attrs, field) do
        value when is_binary(value) ->
          if String.trim(value) != "",
            do: {:cont, :ok},
            else: {:halt, {:error, {:missing_field, field}}}

        _ ->
          {:halt, {:error, {:missing_field, field}}}
      end
    end)
  end

  defp validate_resource(value) do
    if Map.has_key?(@resources, value), do: :ok, else: {:error, {:invalid_resource, value}}
  end

  defp validate_status(value) do
    if Map.has_key?(@statuses, value), do: :ok, else: {:error, {:invalid_status, value}}
  end
end
