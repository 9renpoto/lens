defmodule Lens.Earnings.PDFExtractor do
  @moduledoc "Local Poppler extraction using the bounded Linux process runner."

  def extract(bytes, options \\ []) do
    directory = Path.join(System.tmp_dir!(), "lens-original-#{Ecto.UUID.generate()}")
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)

    try do
      path = Path.join(directory, "original.pdf")
      File.write!(path, bytes)
      python = Keyword.get(options, :python, System.find_executable("python3"))
      executable = Keyword.get(options, :executable, System.find_executable("pdftotext"))

      if is_binary(python) and is_binary(executable) do
        run(python, executable, path, options)
      else
        {:error, %{version: "unavailable", reason: "extractor_unavailable"}}
      end
    after
      File.rm_rf!(directory)
    end
  rescue
    _error in [File.Error, ErlangError] ->
      {:error, %{version: "unavailable", reason: "process_error"}}
  end

  defp run(python, executable, path, options) do
    runner = Application.app_dir(:lens, "priv/pdf_runner.py")
    timeout = Keyword.get(options, :timeout_ms, 20_000) / 1_000
    limit = Keyword.get(options, :max_output_bytes, 8_388_608)
    args = [runner, executable, path, to_string(timeout), to_string(limit)]

    case System.cmd(python, args, stderr_to_stdout: true) do
      {output, 0} -> decode(output)
      _ -> {:error, %{version: "unavailable", reason: "process_error"}}
    end
  end

  defp decode(output) do
    case Jason.decode(output) do
      {:ok, %{"version" => version, "text" => text}} ->
        {:ok, %{version: version, text: text}}

      {:ok, %{"version" => version, "failure" => reason}} ->
        {:error, %{version: version, reason: reason}}

      _ ->
        {:error, %{version: "unavailable", reason: "process_error"}}
    end
  end
end
