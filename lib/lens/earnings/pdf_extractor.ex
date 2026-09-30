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

    case File.stat(text_path) do
      {:ok, %{type: :regular, size: size}} when size <= limit ->
        text = File.read!(text_path)

        cond do
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
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} when size <= 2048 ->
        path |> File.read!() |> replace_invalid_utf8() |> String.trim()

      _ ->
        "unavailable"
    end
  end

  defp replace_invalid_utf8(<<>>), do: ""

  defp replace_invalid_utf8(<<point::utf8, rest::binary>>),
    do: <<point::utf8>> <> replace_invalid_utf8(rest)

  defp replace_invalid_utf8(<<_byte, rest::binary>>), do: "�" <> replace_invalid_utf8(rest)

  defp blank?(text) do
    text
    |> String.to_charlist()
    |> Enum.all?(fn point ->
      point in 9..13 or point in 28..32 or
        point in [0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000] or
        point in 0x2000..0x200A
    end)
  end

  defp failure(reason, version \\ "unavailable"),
    do: {:error, %{version: version, reason: reason}}
end
