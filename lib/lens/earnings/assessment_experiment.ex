defmodule Lens.Earnings.AssessmentExperiment do
  @moduledoc "Read-only labelled-text evaluation; never creates application assessments."
  alias Lens.Earnings.AssessmentExperiment.Ollama

  @heading ~r/^[ \t]*[0-9]{4}\s*年\s*[0-9]{1,2}\s*月期\s*(?:第\s*[123]\s*四半期\s*(?:\(中間期\)\s*)?)?決算説明(?:資料|会資料)[ \t]*\r?$/mu

  def run(cases, client) do
    if valid_cases?(cases) do
      with {:ok, model} <- Ollama.model(client) do
        results = Enum.map(cases, &evaluate(&1, client))
        final_model = Ollama.model(client)

        {:ok,
         %{
           "model" => model,
           "model_stable" => final_model == {:ok, model},
           "contract" => Ollama.contract(client),
           "results" => results,
           "summary" => summarize(results)
         }}
      end
    else
      {:error, :invalid_cases}
    end
  end

  defp valid_cases?(cases) when is_list(cases) and length(cases) in 1..100 do
    Enum.all?(cases, fn
      %{"id" => id, "text" => text, "expected" => expected} ->
        is_binary(id) and byte_size(id) in 1..100 and is_binary(text) and
          byte_size(text) > 0 and Ollama.valid_prediction?(expected)

      _ ->
        false
    end) and length(Enum.uniq_by(cases, & &1["id"])) == length(cases)
  end

  defp valid_cases?(_), do: false

  defp evaluate(item, client) do
    started = System.monotonic_time(:millisecond)
    result = Ollama.classify(client, item["text"])
    elapsed = System.monotonic_time(:millisecond) - started
    baseline = Regex.match?(@heading, String.normalize(item["text"], :nfkc))
    expected_presentation? = item["expected"]["document_kind"] == "earnings_presentation"

    row = %{
      "id" => item["id"],
      "expected" => item["expected"],
      "duration_ms" => elapsed,
      "text_sha256" => Base.encode16(:crypto.hash(:sha256, item["text"]), case: :lower),
      "regex_presentation" => baseline,
      "regex_presentation_match" => baseline == expected_presentation?
    }

    case result do
      {:ok, prediction} ->
        matches =
          Map.new(Ollama.fields(), &{&1, prediction["prediction"][&1] == item["expected"][&1]})

        row
        |> Map.merge(prediction)
        |> Map.merge(%{
          "status" => "ok",
          "field_matches" => matches,
          "exact_match" => Enum.all?(matches, &elem(&1, 1)),
          "model_presentation_match" =>
            prediction["prediction"]["document_kind"] == "earnings_presentation" ==
              expected_presentation?
        })

      {:error, reason} ->
        Map.merge(row, %{
          "status" => "error",
          "error" => Atom.to_string(reason),
          "exact_match" => false,
          "model_presentation_match" => false
        })
    end
  end

  defp summarize(results) do
    %{
      "total" => length(results),
      "completed" => Enum.count(results, &(&1["status"] == "ok")),
      "exact_matches" => Enum.count(results, & &1["exact_match"]),
      "field_matches" =>
        Map.new(Ollama.fields(), fn field ->
          {field, Enum.count(results, &(get_in(&1, ["field_matches", field]) == true))}
        end),
      "verbatim_evidence_matches" =>
        Enum.count(results, fn row ->
          row["status"] == "ok" and Enum.all?(row["verbatim_evidence"], &elem(&1, 1))
        end),
      "regex_presentation_matches" => Enum.count(results, & &1["regex_presentation_match"]),
      "model_presentation_matches" => Enum.count(results, & &1["model_presentation_match"]),
      "duration_ms" => Enum.sum(Enum.map(results, & &1["duration_ms"]))
    }
  end
end
