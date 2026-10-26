# Explicit comparison-only command; no application or database is started.
alias Lens.Earnings.AssessmentExperiment
alias Lens.Earnings.AssessmentExperiment.Ollama

case System.argv() do
  [input, output] ->
    {:ok, _} = Application.ensure_all_started(:req)

    options = [
      endpoint: System.get_env("LENS_OLLAMA_ENDPOINT"),
      model: System.get_env("LENS_OLLAMA_MODEL"),
      think:
        case System.get_env("LENS_OLLAMA_THINK") do
          "true" -> true
          "false" -> false
          value -> value
        end
    ]

    with {:ok, bytes} <- File.read(input),
         {:ok, cases} <- Jason.decode(bytes),
         {:ok, client} <- Ollama.new(options),
         {:ok, report} <- AssessmentExperiment.run(cases, client),
         :ok <- File.write(output, Jason.encode!(report, pretty: true) <> "\n", [:exclusive]) do
      IO.puts(Jason.encode!(report["summary"]))
      unless report["model_stable"], do: System.halt(2)
    else
      {:error, reason} when is_atom(reason) ->
        IO.puts(:stderr, "Evaluation failed: #{reason}")
        System.halt(1)

      _ ->
        IO.puts(:stderr, "Evaluation failed: invalid input")
        System.halt(1)
    end

  _ ->
    IO.puts(
      :stderr,
      "Usage: mix run --no-start scripts/evaluate_earnings_ollama.exs INPUT.json OUTPUT.json"
    )

    System.halt(1)
end
