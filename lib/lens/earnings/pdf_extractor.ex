defmodule Lens.Earnings.PDFExtractor do
  @moduledoc "Local Poppler extraction using the bounded Linux process runner."
  @failures ~w(timeout output_limit unreadable extractor_unavailable process_error unsupported_platform invalid_options)

  def extract(bytes, options \\ []) do
    helper = Keyword.get(options, :helper, Application.app_dir(:lens, "priv/pdf_runner"))
    executable = Keyword.get(options, :executable, System.find_executable("pdftotext"))

    cond do
      not is_binary(helper) or not File.regular?(helper) ->
        failure("extractor_unavailable")

      Keyword.get(options, :platform, :os.type()) != {:unix, :linux} ->
        failure("unsupported_platform")

      not is_binary(executable) ->
        failure("extractor_unavailable")

      true ->
        supervised(bytes, helper, executable, options)
    end
  end

  defp supervised(bytes, helper, executable, options) do
    owner = self()
    reference = make_ref()

    {worker, monitor} =
      spawn_monitor(fn ->
        Process.flag(:trap_exit, true)
        owner_monitor = Process.monitor(owner)
        result = run(bytes, helper, executable, options, owner_monitor)
        send(owner, {reference, result})
      end)

    receive do
      {^reference, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^worker, _reason} ->
        failure("process_error")
    end
  end

  defp run(bytes, helper, executable, options, owner_monitor) do
    directory = Path.join(System.tmp_dir!(), "lens-original-#{Ecto.UUID.generate()}")
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)

    try do
      source = Path.join(directory, "original.pdf")
      text = Path.join(directory, "text.txt")
      version = Path.join(directory, "version.txt")
      File.write!(source, bytes)
      timeout = Keyword.get(options, :timeout_ms, 20_000)
      limit = Keyword.get(options, :max_output_bytes, 8_388_608)
      args = [executable, source, text, version, to_string(timeout), to_string(limit)]

      port =
        Port.open(
          {:spawn_executable, String.to_charlist(helper)},
          [:binary, :exit_status, :use_stdio, {:args, args}]
        )

      deadline = System.monotonic_time(:millisecond) + min(timeout, 2000) + timeout + 2000

      signal_helper =
        Keyword.get(options, :signal_helper, Application.app_dir(:lens, "priv/pdf_runner"))

      case collect(port, owner_monitor, deadline, "", signal_helper) do
        {:ok, record} -> decode(record, text, version, limit)
        :error -> failure("process_error", read_version(version))
      end
    after
      File.rm_rf!(directory)
    end
  rescue
    _error in [File.Error, ErlangError, ArgumentError] -> failure("process_error")
  end

  defp collect(port, owner_monitor, deadline, output, signal_helper) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:data, data}} when byte_size(output) + byte_size(data) <= 256 ->
        collect(port, owner_monitor, deadline, output <> data, signal_helper)

      {^port, {:exit_status, 0}} ->
        {:ok, output}

      {^port, {:exit_status, _}} ->
        :error

      {:EXIT, ^port, _reason} ->
        :error

      {^port, {:data, _}} ->
        cancel(port, signal_helper)

      {:DOWN, ^owner_monitor, :process, _, _} ->
        cancel(port, signal_helper)
    after
      remaining -> cancel(port, signal_helper)
    end
  end

  defp cancel(port, signal_helper) do
    # Keep the Port open to receive the helper's exit after group cleanup.
    Port.command(port, <<0>>)
    await_cancel(port, System.monotonic_time(:millisecond) + 2000, :term, signal_helper)
  end

  defp await_cancel(port, deadline, stage, signal_helper) do
    budget = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:exit_status, _}} -> :error
      {:EXIT, ^port, _reason} -> :error
      {^port, {:data, _}} -> await_cancel(port, deadline, stage, signal_helper)
    after
      budget ->
        case Port.info(port, :os_pid) do
          {:os_pid, pid} ->
            signal = if stage == :term, do: "TERM", else: "KILL"
            System.cmd(signal_helper, ["--signal", signal, to_string(pid)])
            if stage == :term, do: System.cmd(signal_helper, ["--signal", "CONT", to_string(pid)])
            await_cancel(port, System.monotonic_time(:millisecond) + 2000, :kill, signal_helper)

          nil ->
            :error
        end
    end
  end

  defp decode("ok\n", text_path, version_path, limit) do
    version = read_version(version_path)

    case {File.lstat(text_path), File.lstat(version_path)} do
      {{:ok, %{type: :regular, size: size}}, {:ok, %{type: :regular, size: version_size}}}
      when size <= limit and version_size <= 2048 ->
        text = bounded_read!(text_path, limit)

        cond do
          byte_size(text) > limit ->
            failure("process_error", version)

          not String.valid?(text) or String.contains?(text, <<0>>) ->
            failure("invalid_text", version)

          blank?(text) ->
            failure("empty_output", version)

          true ->
            {:ok, %{text: text, version: version}}
        end

      _ ->
        failure("process_error", version)
    end
  end

  defp decode(record, _text, version, _limit) do
    reason = String.trim_trailing(record, "\n")

    if reason in @failures and record == reason <> "\n",
      do: failure(reason, read_version(version)),
      else: failure("process_error", read_version(version))
  end

  defp read_version(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular, size: size}} when size <= 2048 ->
        path |> bounded_read!(2048) |> replace_invalid_utf8() |> trim_whitespace()

      _ ->
        "unavailable"
    end
  end

  defp bounded_read!(path, limit) do
    {:ok, text} =
      File.open(path, [:read, :binary], fn file ->
        case IO.binread(file, limit + 1) do
          :eof -> ""
          data when is_binary(data) -> data
        end
      end)

    text
  end

  defp trim_whitespace(text) do
    text
    |> String.to_charlist()
    |> Enum.drop_while(&whitespace?/1)
    |> Enum.reverse()
    |> Enum.drop_while(&whitespace?/1)
    |> Enum.reverse()
    |> List.to_string()
  end

  defp replace_invalid_utf8(<<>>), do: ""

  defp replace_invalid_utf8(<<point::utf8, rest::binary>>),
    do: <<point::utf8>> <> replace_invalid_utf8(rest)

  defp replace_invalid_utf8(<<lead, rest::binary>>) do
    {continuations, low, high} =
      cond do
        lead in 0xC2..0xDF -> {1, 0x80, 0xBF}
        lead == 0xE0 -> {2, 0xA0, 0xBF}
        lead == 0xED -> {2, 0x80, 0x9F}
        lead in 0xE1..0xEF -> {2, 0x80, 0xBF}
        lead == 0xF0 -> {3, 0x90, 0xBF}
        lead == 0xF4 -> {3, 0x80, 0x8F}
        lead in 0xF1..0xF3 -> {3, 0x80, 0xBF}
        true -> {0, 0, 0}
      end

    "�" <> replace_invalid_utf8(skip_invalid_prefix(rest, continuations, low, high))
  end

  defp skip_invalid_prefix(<<byte, rest::binary>>, remaining, low, high)
       when remaining > 0 and byte >= low and byte <= high,
       do: skip_invalid_prefix(rest, remaining - 1, 0x80, 0xBF)

  defp skip_invalid_prefix(rest, _remaining, _low, _high), do: rest

  defp blank?(text), do: text |> String.to_charlist() |> Enum.all?(&whitespace?/1)

  defp whitespace?(point) do
    point in 9..13 or point in 28..32 or
      point in [0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000] or
      point in 0x2000..0x200A
  end

  defp failure(reason, version \\ "unavailable"),
    do: {:error, %{version: version, reason: reason}}
end
