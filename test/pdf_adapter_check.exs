ExUnit.start()

defmodule PDFAdapterCheck do
  use ExUnit.Case
  alias Lens.Earnings.PDFExtractor

  test "real Japanese text and version remain exact" do
    {:ok, result} =
      PDFExtractor.extract(File.read!("test/fixtures/earnings-text.pdf"),
        helper: Path.expand("priv/pdf_runner")
      )

    assert result.text =~ "決算短信"
    assert result.text =~ "売上高は１２３億円です。"
    assert result.text =~ "\n\n"
    assert result.version =~ "pdftotext version"
  end

  test "image-only PDF remains empty_output" do
    assert {:error, %{reason: "empty_output"}} =
             PDFExtractor.extract(File.read!("test/fixtures/earnings-image.pdf"),
               helper: Path.expand("priv/pdf_runner")
             )
  end

  test "malformed and oversized status records fail closed" do
    for response <- ["unknown", "ok\nok", String.duplicate("x", 1024)] do
      root = Path.join(System.tmp_dir!(), Ecto.UUID.generate())
      File.mkdir!(root)
      helper = Path.join(root, "helper")
      File.write!(helper, "#!/bin/sh\nprintf '%s\\n' '" <> response <> "'\n")
      File.chmod!(helper, 0o700)

      try do
        assert {:error, %{reason: "process_error"}} = PDFExtractor.extract("pdf", helper: helper)
      after
        File.rm_rf!(root)
      end
    end
  end

  test "Unicode blankness, NUL and invalid UTF-8 retain classifications" do
    root = Path.join(System.tmp_dir!(), Ecto.UUID.generate())
    File.mkdir!(root)
    executable = Path.join(root, "extractor")
    payload = Path.join(root, "payload")

    File.write!(
      executable,
      "#!/bin/sh\nif [ \"$1\" = -v ]; then echo fixture; exit 0; fi\ncp '" <>
        payload <> "' \"$7\"\n"
    )

    File.chmod!(executable, 0o700)

    try do
      for {text, reason} <- [
            {"　\f\u001C", "empty_output"},
            {<<255>>, "invalid_text"},
            {<<0>>, "invalid_text"}
          ] do
        File.write!(payload, text)

        assert {:error, %{reason: ^reason}} =
                 PDFExtractor.extract("pdf",
                   helper: Path.expand("priv/pdf_runner"),
                   executable: executable
                 )
      end
    after
      File.rm_rf!(root)
    end
  end

  test "caller death cancels active extraction and removes its children" do
    root = Path.join(System.tmp_dir!(), Ecto.UUID.generate())
    File.mkdir!(root)
    executable = Path.join(root, "extractor")
    marker = Path.join(root, "marker")
    child_pid = Path.join(root, "pid")

    File.write!(
      executable,
      "#!/bin/sh\nif [ \"$1\" = -v ]; then echo fixture; exit 0; fi\n(sleep 1; echo survived > '" <>
        marker <> "') &\necho $! > '" <> child_pid <> "'\nwait\n"
    )

    File.chmod!(executable, 0o700)

    try do
      owner =
        spawn(fn ->
          PDFExtractor.extract("pdf",
            helper: Path.expand("priv/pdf_runner"),
            executable: executable
          )
        end)

      wait_until(fn -> File.exists?(child_pid) end)
      pid = File.read!(child_pid) |> String.trim()
      Process.exit(owner, :kill)
      wait_until(fn -> not File.exists?("/proc/" <> pid) end)
      Process.sleep(1200)
      refute File.exists?(marker)
    after
      File.rm_rf!(root)
    end
  end

  test "outer deadline terminates a stuck helper" do
    root = Path.join(System.tmp_dir!(), Ecto.UUID.generate())
    File.mkdir!(root)
    helper = Path.join(root, "helper")
    File.write!(helper, "#!/bin/sh\nexec sleep 30\n")
    File.chmod!(helper, 0o700)

    try do
      started = System.monotonic_time(:millisecond)

      assert {:error, %{reason: "process_error"}} =
               PDFExtractor.extract("pdf",
                 helper: helper,
                 signal_helper: Path.expand("priv/pdf_runner"),
                 timeout_ms: 1
               )

      assert System.monotonic_time(:millisecond) - started < 6500
    after
      File.rm_rf!(root)
    end
  end

  defp wait_until(predicate, remaining \\ 200) do
    if predicate.() do
      :ok
    else
      assert remaining > 0
      Process.sleep(10)
      wait_until(predicate, remaining - 1)
    end
  end

  test "version replacement groups incomplete UTF-8 like the reference runner" do
    root = Path.join(System.tmp_dir!(), Ecto.UUID.generate())
    File.mkdir!(root)
    executable = Path.join(root, "extractor")
    payload = Path.join(root, "version")
    File.write!(payload, <<"fixture ", 0xE3, 0x81>>)

    File.write!(
      executable,
      "#!/bin/sh\nif [ \"$1\" = -v ]; then cat '" <>
        payload <> "'; exit 0; fi\nprintf text > \"$7\"\n"
    )

    File.chmod!(executable, 0o700)

    try do
      assert {:ok, %{version: "fixture �"}} =
               PDFExtractor.extract("pdf",
                 helper: Path.expand("priv/pdf_runner"),
                 executable: executable
               )
    after
      File.rm_rf!(root)
    end
  end

  test "concurrent extractions keep independent files and exact bytes" do
    pdf = File.read!("test/fixtures/earnings-text.pdf")
    {:ok, expected} = PDFExtractor.extract(pdf, helper: Path.expand("priv/pdf_runner"))

    results =
      Task.async_stream(
        1..12,
        fn _ -> PDFExtractor.extract(pdf, helper: Path.expand("priv/pdf_runner")) end,
        max_concurrency: 6
      )

    for result <- results, do: assert(result == {:ok, {:ok, expected}})
  end

  test "missing Poppler and unlaunchable helper fail closed" do
    assert {:error, %{reason: "extractor_unavailable"}} =
             PDFExtractor.extract("pdf", helper: Path.expand("priv/pdf_runner"), executable: nil)

    root = Path.join(System.tmp_dir!(), Ecto.UUID.generate())
    File.mkdir!(root)
    helper = Path.join(root, "helper")
    File.write!(helper, "not executable")

    try do
      assert {:error, %{reason: "process_error"}} = PDFExtractor.extract("pdf", helper: helper)
    after
      File.rm_rf!(root)
    end
  end

  test "success without output metadata is rejected and enumerated failure is preserved" do
    root = Path.join(System.tmp_dir!(), Ecto.UUID.generate())
    File.mkdir!(root)
    helper = Path.join(root, "helper")
    File.chmod!(root, 0o700)

    try do
      for {record, reason} <- [{"ok", "process_error"}, {"timeout", "timeout"}] do
        File.write!(helper, "#!/bin/sh\necho " <> record <> "\n")
        File.chmod!(helper, 0o700)
        assert {:error, %{reason: ^reason}} = PDFExtractor.extract("pdf", helper: helper)
      end
    after
      File.rm_rf!(root)
    end
  end

  test "invalid version bytes retain reference replacement for every UTF-8 lead width" do
    root = Path.join(System.tmp_dir!(), Ecto.UUID.generate())
    File.mkdir!(root)
    executable = Path.join(root, "extractor")
    payload = Path.join(root, "version")

    File.write!(
      executable,
      "#!/bin/sh\nif [ \"$1\" = -v ]; then cat '" <>
        payload <> "'; exit 0; fi\nprintf text > \"$7\"\n"
    )

    File.chmod!(executable, 0o700)

    try do
      for bytes <- [<<0xF0, 0x90>>, <<0xF4, 0x8F>>, <<0xF1, 0x80>>, <<255>>] do
        File.write!(payload, bytes)

        assert {:ok, %{version: "�"}} =
                 PDFExtractor.extract("pdf",
                   helper: Path.expand("priv/pdf_runner"),
                   executable: executable
                 )
      end
    after
      File.rm_rf!(root)
    end
  end

  test "missing native helper fails closed" do
    assert {:error, %{reason: "extractor_unavailable", version: "unavailable"}} =
             PDFExtractor.extract("pdf", helper: nil, executable: "/usr/bin/true")
  end

  test "callable helper on non-Linux is rejected before launch" do
    assert {:error, %{reason: "unsupported_platform"}} =
             PDFExtractor.extract("pdf", helper: "/usr/bin/true", platform: {:unix, :darwin})
  end

  test "native protocol never accepts an empty or unknown response" do
    assert {:error, %{reason: "process_error"}} =
             PDFExtractor.extract("pdf", helper: "/usr/bin/true", executable: "/usr/bin/true")
  end
end
