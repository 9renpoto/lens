defmodule Mix.Tasks.Lens.Earnings.BriefTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias Mix.Tasks.Lens.Earnings.Brief

  @fixture_path "test/fixtures/earnings/brief_example.json"
  @env_keys ~w(LENS_OLLAMA_ENDPOINT LENS_OLLAMA_MODEL LENS_OLLAMA_THINK LENS_OLLAMA_TIMEOUT_MS)

  setup do
    previous = Map.new(@env_keys, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    Enum.each(@env_keys, &System.delete_env/1)
    :ok
  end

  test "prints cited disclosure facts only when --facts-only is passed" do
    output = capture_io(fn -> Brief.run(["--facts-only", @fixture_path]) end)

    assert output =~ "## 開示ファクト"
    assert output =~ "出典: 架空工業 2026年3月期 第2四半期 決算短信 p.4「研究開発・人材投資」"
    assert output =~ "> 第2四半期にクラウド基盤チームの採用を前年度比で拡大し、専任体制を立ち上げる計画。"
    refute output =~ "## 仕事の需要仮説（推測）"
  end

  test "generates a distinct hypothesis and verification step with a configured local model" do
    payload = %{
      "work_type" => "クラウド基盤エンジニア",
      "demand_direction" => "increase",
      "reason" => "専任体制の立ち上げ計画により、クラウド基盤人材の需要が高まる可能性があるため。",
      "verification_step" => "公式採用ページでクラウド基盤エンジニアの新規求人と必須スキルを確認する。",
      "next_step" => "既存の開発経験にクラウドネットワークと IaC の基礎を組み合わせる。"
    }

    System.put_env(
      "LENS_OLLAMA_ENDPOINT",
      start_stub_ollama(ok_tags(), ok_chat(Jason.encode!(payload)))
    )

    System.put_env("LENS_OLLAMA_MODEL", "gpt-oss:20b")

    output = capture_io(fn -> Brief.run([@fixture_path]) end)

    assert output =~ "## 開示ファクト"
    assert output =~ "## 仕事の需要仮説（推測）"
    assert output =~ "根拠出典: 架空工業 2026年3月期 第2四半期 決算短信 p.4「研究開発・人材投資」"
    assert output =~ "変化しうる仕事: クラウド基盤エンジニア"
    assert output =~ "## 一次情報での確認方法"
    assert output =~ "## 任意の次の一歩"
  end

  test "shows cited facts and visible failure when model is unconfigured, unavailable, or invalid" do
    unconfigured =
      capture_io(fn ->
        assert_raise Mix.Error, ~r/LENS_OLLAMA_ENDPOINT/, fn -> Brief.run([@fixture_path]) end
      end)

    assert unconfigured =~ "## 開示ファクト" and unconfigured =~ "生成失敗:"

    for {tags, chat, expected} <- [
          {%{"models" => []}, %{}, ~r/model_unavailable/},
          {ok_tags(), ok_chat("not-json"), ~r/invalid_output/}
        ] do
      System.put_env("LENS_OLLAMA_ENDPOINT", start_stub_ollama(tags, chat))
      System.put_env("LENS_OLLAMA_MODEL", "gpt-oss:20b")

      output =
        capture_io(fn ->
          assert_raise Mix.Error, expected, fn -> Brief.run([@fixture_path]) end
        end)

      assert output =~ "## 開示ファクト" and output =~ "生成失敗:"
    end
  end

  test "fails visibly when required evidence is missing or status is invalid" do
    base = @fixture_path |> File.read!() |> Jason.decode!()

    incomplete = write_temp_raw(Jason.encode!(Map.delete(base, "source_locator")))
    invalid_status = write_temp_raw(Jason.encode!(Map.put(base, "status", "rumored")))
    invalid_json = write_temp_raw("{not valid json")

    assert_raise Mix.Error, ~r/source_locator/, fn -> Brief.run(["--facts-only", incomplete]) end

    assert_raise Mix.Error, ~r/status.*actual.*planned/, fn ->
      Brief.run(["--facts-only", invalid_status])
    end

    assert_raise Mix.Error, ~r/JSON/, fn -> Brief.run(["--facts-only", invalid_json]) end
    assert_raise Mix.Error, ~r/Usage: mix lens\.earnings\.brief/, fn -> Brief.run([]) end
  end

  defp ok_tags, do: %{"models" => [%{"name" => "gpt-oss:20b", "digest" => "sha256:test"}]}

  defp ok_chat(content),
    do: %{"done" => true, "done_reason" => "stop", "message" => %{"content" => content}}

  defp start_stub_ollama(tags_body, chat_body) do
    plug = fn conn, _opts ->
      body = if conn.request_path == "/api/tags", do: tags_body, else: chat_body

      conn
      |> Plug.Conn.put_resp_header("content-type", "application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(body))
    end

    server =
      start_supervised!(
        {Bandit, plug: plug, ip: {127, 0, 0, 1}, port: 0, startup_log: false},
        id: {:stub_ollama, System.unique_integer([:positive])}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    "http://127.0.0.1:#{port}"
  end

  defp write_temp_raw(content) do
    path = Path.join(System.tmp_dir!(), "lens_brief_#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
