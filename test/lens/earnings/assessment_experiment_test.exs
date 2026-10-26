defmodule Lens.Earnings.AssessmentExperimentTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  alias Lens.Earnings.AssessmentExperiment
  alias Lens.Earnings.AssessmentExperiment.Ollama

  @cases "test/fixtures/earnings/assessment_experiment.json" |> File.read!() |> Jason.decode!()
  @digest "sha256:" <> String.duplicate("a", 64)

  test "sends only source text, structured schema and bounded settings to the selected local model" do
    owner = self()

    client =
      client(fn conn ->
        body = Jason.decode!(Req.Test.raw_body(conn))
        send(owner, {:request, conn.request_path, body})
        json(conn, response(hd(@cases)))
      end)

    assert {:ok, result} = Ollama.classify(client, hd(@cases)["text"])
    assert result["prediction"] == hd(@cases)["expected"]
    assert_receive {:request, "/api/chat", body}
    assert body["model"] == "fixture-model:latest"
    assert body["stream"] == false
    refute Map.has_key?(body, "think")
    assert body["format"]["type"] == "object"
    assert body["options"]["num_ctx"] == 8192
    assert body["options"]["num_predict"] == 1024
    assert body["messages"] |> List.last() |> Map.fetch!("content") == hd(@cases)["text"]
    refute Map.has_key?(body, "expected")
    refute inspect(result) =~ "private reasoning"
  end

  test "optional thinking controls are explicit settings for any selected model" do
    owner = self()

    for think <- ["low", "high", false, true] do
      client =
        client(
          fn conn ->
            body = Jason.decode!(Req.Test.raw_body(conn))
            send(owner, {:settings, body["model"], body["think"]})
            json(conn, response(hd(@cases)))
          end,
          model: "another-fixture-model:v2",
          think: think
        )

      assert {:ok, _} = Ollama.classify(client, hd(@cases)["text"])
      assert_receive {:settings, "another-fixture-model:v2", ^think}
      assert Ollama.contract(client)["think"] == think
    end
  end

  test "scores complete runs including failures and reports the limited heading baseline separately" do
    cases = Enum.take(@cases, 3)

    client =
      client(fn conn ->
        case conn.request_path do
          "/api/tags" ->
            json(conn, %{"models" => [%{"name" => "fixture-model:latest", "digest" => @digest}]})

          "/api/chat" ->
            body = Jason.decode!(Req.Test.raw_body(conn))
            text = List.last(body["messages"])["content"]

            case Enum.find(cases, &(&1["text"] == text)) do
              %{"id" => "regular"} -> send_resp(conn, 503, "private upstream error")
              item -> json(conn, response(item))
            end
        end
      end)

    assert {:ok, report} = AssessmentExperiment.run(cases, client)
    assert report["model"]["digest"] == @digest
    assert report["summary"]["total"] == 3
    assert report["summary"]["completed"] == 2
    assert report["summary"]["exact_matches"] == 2
    assert report["summary"]["field_matches"]["document_kind"] == 2
    assert report["summary"]["regex_presentation_matches"] == 2
    assert report["summary"]["model_presentation_matches"] == 2
    assert List.last(report["results"])["error"] == "http_error"
    assert byte_size(hd(report["results"])["text_sha256"]) == 64
    refute Jason.encode!(report) =~ "private upstream error"
    refute Jason.encode!(report) =~ "example.test"
  end

  test "flags fabricated evidence without treating literal membership as semantic proof" do
    item = hd(@cases)
    payload = response(item)
    content = Jason.decode!(payload["message"]["content"])

    payload =
      put_in(
        payload,
        ["message", "content"],
        Jason.encode!(put_in(content, ["evidence", "issuer_code"], "invented"))
      )

    assert {:ok, result} = Ollama.classify(client(&json(&1, payload)), item["text"])
    refute result["verbatim_evidence"]["issuer_code"]
    assert result["verbatim_evidence"]["period"]
  end

  test "a wrong answer can quote real text and pass binary detection without matching its kind" do
    item = Enum.find(@cases, &(&1["id"] == "regular"))
    wrong = put_in(item, ["expected", "document_kind"], "other")

    client =
      client(fn conn ->
        if conn.request_path == "/api/tags",
          do:
            json(conn, %{"models" => [%{"name" => "fixture-model:latest", "digest" => @digest}]}),
          else: json(conn, response(wrong))
      end)

    assert {:ok, report} = AssessmentExperiment.run([item], client)
    assert report["summary"]["exact_matches"] == 0
    assert report["summary"]["field_matches"]["document_kind"] == 0
    assert report["summary"]["field_matches"]["issuer_code"] == 1
    assert report["summary"]["model_presentation_matches"] == 1
    assert report["summary"]["verbatim_evidence_matches"] == 1
  end

  test "rejects invalid JSON, schema mismatches and incomplete generation" do
    for payload <- [
          %{"done" => true, "done_reason" => "stop", "message" => %{"content" => "not json"}},
          %{"done" => true, "done_reason" => "stop", "message" => %{"content" => "{}"}},
          %{"done" => true, "done_reason" => "stop", "message" => %{"content" => "null"}},
          %{"done" => true, "done_reason" => "stop", "message" => %{"content" => "[]"}},
          Map.put(response(hd(@cases)), "done_reason", "length"),
          Map.put(response(hd(@cases)), "done", false)
        ] do
      assert {:error, :invalid_output} =
               Ollama.classify(client(&json(&1, payload)), hd(@cases)["text"])
    end
  end

  test "bounds input, response size and wall time without retries" do
    never = client(fn _ -> flunk("oversized input reached the server") end)
    assert {:error, :input_limit} = Ollama.classify(never, String.duplicate("a", 12_001))

    assert {:error, :response_limit} =
             Ollama.classify(
               client(&send_resp(&1, 200, String.duplicate("a", 1_048_577))),
               "text"
             )

    slow =
      client(
        fn conn ->
          Process.sleep(200)
          json(conn, response(hd(@cases)))
        end,
        timeout_ms: 20
      )

    assert {:error, :timeout} = Ollama.classify(slow, "text")
  end

  test "does not follow redirects or expose HTTP error bodies" do
    client =
      client(fn conn ->
        conn
        |> put_resp_header("location", "https://external.invalid/")
        |> send_resp(302, "private")
      end)

    assert {:error, :http_error} = Ollama.classify(client, "text")
  end

  test "requires a locally available model digest and detects tag changes" do
    client = client(fn conn -> json(conn, %{"models" => []}) end)
    assert {:error, :model_unavailable} = AssessmentExperiment.run(@cases, client)
    {:ok, calls} = Agent.start_link(fn -> 0 end)
    on_exit(fn -> if Process.alive?(calls), do: Agent.stop(calls) end)

    client =
      client(fn conn ->
        case conn.request_path do
          "/api/tags" ->
            digest =
              Agent.get_and_update(calls, fn n ->
                {if(n == 0, do: @digest, else: "changed"), n + 1}
              end)

            json(conn, %{"models" => [%{"name" => "fixture-model:latest", "digest" => digest}]})

          "/api/chat" ->
            json(conn, response(hd(@cases)))
        end
      end)

    assert {:ok, report} = AssessmentExperiment.run([hd(@cases)], client)
    refute report["model_stable"]
  end

  test "validates the whole labelled dataset before inference and keeps null expectations meaningful" do
    client = client(fn _ -> flunk("invalid cases reached the server") end)
    assert {:error, :invalid_cases} = AssessmentExperiment.run([], client)
    assert {:error, :invalid_cases} = AssessmentExperiment.run([hd(@cases), hd(@cases)], client)

    assert {:error, :invalid_cases} =
             AssessmentExperiment.run([Map.delete(hd(@cases), "expected")], client)

    item = Enum.find(@cases, &(&1["id"] == "unknown-period"))

    client =
      client(fn conn ->
        if conn.request_path == "/api/tags",
          do:
            json(conn, %{"models" => [%{"name" => "fixture-model:latest", "digest" => @digest}]}),
          else: json(conn, response(item))
      end)

    assert {:ok, report} = AssessmentExperiment.run([item], client)
    assert report["summary"]["exact_matches"] == 1
  end

  test "configuration rejects malformed endpoints and invalid limits" do
    for options <- [
          [],
          [endpoint: "file:///private/data", model: "fixture-model:latest"],
          [endpoint: "http://localhost:11434", model: ""],
          [endpoint: "http://localhost:11434", model: "fixture-model:latest", timeout_ms: 0]
        ] do
      assert {:error, :invalid_configuration} = Ollama.new(options)
    end
  end

  defp client(plug, options \\ []) do
    {:ok, client} =
      Ollama.new(
        Keyword.merge([endpoint: "http://example.test", model: "fixture-model:latest"], options)
      )

    %{client | request: Req.merge(client.request, plug: plug)}
  end

  defp response(item) do
    evidence =
      Map.new(item["expected"], fn {field, value} ->
        {field, if(is_nil(value), do: nil, else: item["text"])}
      end)

    %{
      "done" => true,
      "done_reason" => "stop",
      "message" => %{
        "thinking" => "private reasoning",
        "content" => Jason.encode!(Map.put(item["expected"], "evidence", evidence))
      }
    }
  end

  defp json(conn, body),
    do:
      conn
      |> put_resp_header("content-type", "application/json")
      |> send_resp(200, Jason.encode!(body))
end
