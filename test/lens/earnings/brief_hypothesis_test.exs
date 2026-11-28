defmodule Lens.Earnings.Brief.HypothesisTest do
  use ExUnit.Case, async: true
  import Plug.Conn

  alias Lens.Earnings.AssessmentExperiment.Ollama
  alias Lens.Earnings.Brief
  alias Lens.Earnings.Brief.Hypothesis

  @fixture_path "test/fixtures/earnings/brief_example.json"
  @digest "sha256:" <> String.duplicate("b", 64)

  test "sends only validated facts to Ollama and renders distinct hypothesis and check sections" do
    {:ok, brief} = Brief.load_file(@fixture_path)
    owner = self()

    payload = %{
      "work_type" => "クラウドインフラエンジニア / SRE",
      "demand_direction" => "increase",
      "reason" => "専任チームの採用拡大計画により、クラウド基盤人材の需要が増える可能性があるため。",
      "verification_step" => "公式採用ページでクラウド基盤・SRE関連の新規求人数と募集要件を確認する。",
      "next_step" => "既存のバックエンド開発経験に Terraform とコンテナ運用の基礎を組み合わせる。"
    }

    client =
      stub_client(fn conn ->
        if conn.request_path == "/api/tags" do
          json(conn, %{"models" => [%{"name" => "gpt-oss:20b", "digest" => @digest}]})
        else
          send(owner, {:chat_request, Jason.decode!(Req.Test.raw_body(conn))})
          json(conn, chat_response(Jason.encode!(payload)))
        end
      end)

    assert {:ok, hypothesis} = Hypothesis.generate(brief, client)
    assert_received {:chat_request, body}
    assert body["model"] == "gpt-oss:20b"
    assert is_map(body["format"])

    user_json =
      body["messages"]
      |> Enum.find(&(&1["role"] == "user"))
      |> Map.fetch!("content")
      |> Jason.decode!()

    assert Enum.sort(Map.keys(user_json)) == ~w(action activity excerpt resource status)
    assert user_json["excerpt"] == brief.excerpt

    rendered = Brief.render(brief, {:ok, hypothesis})
    assert rendered =~ "## 開示ファクト"
    assert rendered =~ "出典: #{brief.source_locator}"
    assert rendered =~ "## 仕事の需要仮説（推測）"
    assert rendered =~ "根拠出典: #{brief.source_locator}"
    assert rendered =~ "見込み方向: 需要増加 (increase)"
    assert rendered =~ "## 一次情報での確認方法"
    assert rendered =~ "## 任意の次の一歩"
  end

  test "omits optional next step section when model returns null" do
    {:ok, brief} = Brief.load_file(@fixture_path)

    payload = %{
      "work_type" => "既存オンプレミス運用担当",
      "demand_direction" => "decrease",
      "reason" => "クラウド基盤への体制シフトに伴い、従来運用の比重が下がる可能性があるため。",
      "verification_step" => "公式採用ページで従来インフラ運用の求人が縮小していないか確認する。",
      "next_step" => nil
    }

    client = stub_chat(chat_response(Jason.encode!(payload)))
    assert {:ok, hypothesis} = Hypothesis.generate(brief, client)
    assert is_nil(hypothesis.next_step)
    rendered = Brief.render(brief, {:ok, hypothesis})
    assert rendered =~ "見込み方向: 需要減少 (decrease)"
    refute rendered =~ "## 任意の次の一歩"
  end

  test "surfaces model unavailability and invalid responses visibly" do
    {:ok, brief} = Brief.load_file(@fixture_path)
    unavailable = stub_client(&json(&1, %{"models" => []}))
    assert {:error, :model_unavailable} = Hypothesis.generate(brief, unavailable)

    invalid_direction = %{
      "work_type" => "SRE",
      "demand_direction" => "sideways",
      "reason" => "r",
      "verification_step" => "v",
      "next_step" => nil
    }

    for bad <- [
          chat_response("not json"),
          chat_response("{}"),
          chat_response(Jason.encode!(invalid_direction)),
          chat_response(
            Jason.encode!(
              Map.put(invalid_direction, "demand_direction", "increase")
              |> Map.put("work_type", "  ")
            )
          ),
          Map.put(chat_response("{}"), "done_reason", "length")
        ] do
      assert {:error, :invalid_output} = Hypothesis.generate(brief, stub_chat(bad))
    end

    failed = Brief.render(brief, {:error, :model_unavailable})
    assert failed =~ "## 開示ファクト"
    assert failed =~ "出典: #{brief.source_locator}"
    assert failed =~ "生成失敗:"
    assert failed =~ "model_unavailable"
  end

  defp stub_chat(chat_body) do
    stub_client(fn conn ->
      if conn.request_path == "/api/tags",
        do: json(conn, %{"models" => [%{"name" => "gpt-oss:20b", "digest" => @digest}]}),
        else: json(conn, chat_body)
    end)
  end

  defp stub_client(plug) do
    {:ok, client} = Ollama.new(endpoint: "http://example.test", model: "gpt-oss:20b")
    %{client | request: Req.merge(client.request, plug: plug)}
  end

  defp chat_response(content),
    do: %{"done" => true, "done_reason" => "stop", "message" => %{"content" => content}}

  defp json(conn, body),
    do:
      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(200, Jason.encode!(body))
end
