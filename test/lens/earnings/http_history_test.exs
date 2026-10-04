defmodule Lens.Earnings.HTTPHistoryTest do
  use Lens.DataCase
  alias Lens.Earnings
  alias Lens.Earnings.{Acquisition, HTTP, HTTPHistory, HTTPCheck, Original}

  @at ~U[2026-10-02 00:00:00.000000Z]
  @url "https://example.test/request.pdf"
  @final "https://example.test/actual.pdf"

  test "persists an original and distinct publisher/acquisition facts atomically" do
    attrs = attrs("first", :success, "%PDF-first") |> Map.put(:published_on, ~D[2026-07-29])
    assert {:ok, check} = HTTPHistory.record(attrs)
    assert check.status == "success"
    assert check.url == @url
    assert check.final_url == @final
    assert check.published_on == ~D[2026-07-29]
    assert check.checked_at == @at
    acquisition = Repo.get!(Acquisition, check.acquisition_id)
    assert acquisition.url == @final
    assert acquisition.acquired_at == @at
    assert acquisition.release_id
    assert Earnings.original_bytes(acquisition.original_id) == {:ok, "%PDF-first"}
    assert check.sha256 == Repo.get!(Original, acquisition.original_id).sha256
  end

  test "304 creates a check without fabricating downloaded bytes or acquisition history" do
    assert {:ok, _} = HTTPHistory.record(attrs("download", :success, "%PDF-first"))
    assert {:ok, check} = HTTPHistory.record(attrs("unchanged", :not_modified, nil))
    assert check.status == "not_modified"
    assert check.acquisition_id == nil
    assert check.sha256 == nil
    assert check.byte_size == nil
    assert Repo.aggregate(Acquisition, :count) == 1
    assert Repo.aggregate(Original, :count) == 1
  end

  test "304 checks require the final response URL" do
    input = put_in(attrs("missing-final-url", :not_modified, nil), [:result, :final_url], nil)

    assert {:error, %Ecto.Changeset{valid?: false}} = HTTPHistory.record(input)
    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "started failures require a valid final response URL" do
    for final_url <- [nil, "mailto:failure@example.test"] do
      input =
        attrs("failure-final-url-#{inspect(final_url)}", :failed, nil)
        |> put_in([:result, :final_url], final_url)

      assert {:error, _} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "completed successful outcomes cannot be retryable" do
    inputs =
      for outcome <- [:success, :not_modified] do
        put_in(
          attrs(
            "retryable-#{outcome}",
            outcome,
            if(outcome == :success, do: "%PDF-valid", else: nil)
          ),
          [:result, :retryable],
          true
        )
      end

    for input <- inputs do
      assert {:error, _} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "failed outcomes reject retryability that contradicts the failure reason or HTTP status" do
    cases = [
      {:non_pdf, 200, true},
      {:too_large, 200, true},
      {:unsupported_encoding, 200, true},
      {:url_not_allowed, nil, true},
      {:redirect_limit, 302, true},
      {:timeout, nil, false},
      {:interrupted, nil, false},
      {:transport_error, nil, false},
      {:http_error, 404, true},
      {:http_error, 503, false},
      {:http_error, 429, false}
    ]

    for {reason, status, retryable} <- cases do
      input =
        attrs("retryability-#{reason}-#{status}", :failed, nil)
        |> put_in([:result, :failure_reason], reason)
        |> put_in([:result, :http_status], status)
        |> put_in([:result, :headers], if(is_nil(status), do: %{}, else: %{"etag" => "v1"}))
        |> put_in([:result, :retryable], retryable)

      assert {:error, _} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "failed outcomes reject response facts that contradict their failure reason" do
    cases = [
      {:timeout, 503, %{"etag" => "v1"}, 1},
      {:timeout, nil, %{"etag" => "v1"}, 1},
      {:interrupted, 200, %{}, 1},
      {:transport_error, 503, %{}, 1},
      {:url_not_allowed, 302, %{"location" => @final}, 1},
      {:invalid_options, nil, %{}, 1},
      {:non_pdf, 503, %{}, 1},
      {:unsupported_encoding, 304, %{}, 1},
      {:redirect_limit, 200, %{}, 1},
      {:invalid_redirect, 404, %{}, 1},
      {:http_error, nil, %{}, 1},
      {:http_error, 200, %{}, 1},
      {:http_error, 304, %{}, 1},
      {:http_error, 302, %{}, 1},
      {:too_large, 503, %{}, 1},
      {:too_large, nil, %{"etag" => "v1"}, 1},
      {:unknown_failure, nil, %{}, 1}
    ]

    for {{reason, status, headers, requests}, index} <- Enum.with_index(cases) do
      input =
        attrs("response-facts-#{index}", :failed, nil)
        |> put_in([:result, :failure_reason], reason)
        |> put_in([:result, :http_status], status)
        |> put_in([:result, :headers], headers)
        |> put_in([:result, :requests], requests)
        |> put_in([:result, :retryable], reason in [:timeout, :interrupted, :transport_error])

      assert {:error, %Ecto.Changeset{valid?: false}} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
    assert Repo.aggregate(Original, :count) == 0
  end

  test "a denied non-HTTP redirect retains the evaluated URL and can be persisted again" do
    target = "mailto:test@example.com"
    url = redirect_server(target)
    result = HTTP.fetch(url, allowed_url?: &(&1 == url))
    assert result.failure_reason == :url_not_allowed
    assert result.requests == 1
    assert result.final_url == target

    input =
      attrs("denied-redirect", :failed, nil) |> Map.put(:url, url) |> Map.put(:result, result)

    assert {:ok, check} = HTTPHistory.record(input)
    assert check.url == url
    assert check.final_url == target
    assert check.http_status == nil
    assert check.response_headers == %{}
    acquisition = Repo.get!(Acquisition, check.acquisition_id)
    assert acquisition.url == url
    assert acquisition.failure_reason == "url_not_allowed"
    assert {:ok, ^check} = HTTPHistory.record(input)
    assert Repo.aggregate(HTTPCheck, :count) == 1
    assert Repo.aggregate(Acquisition, :count) == 1
    assert Repo.aggregate(Original, :count) == 0
  end

  test "identical reacquisition adds history while changed bytes preserve old originals" do
    for {id, bytes} <- [{"one", "%PDF-one"}, {"two", "%PDF-one"}, {"three", "%PDF-two"}] do
      assert {:ok, _} = HTTPHistory.record(attrs(id, :success, bytes))
    end

    assert Repo.aggregate(HTTPCheck, :count) == 3
    assert Repo.aggregate(Acquisition, :count) == 3
    assert Repo.aggregate(Original, :count) == 2

    assert Enum.sort(Enum.map(Repo.all(Original), &elem(Earnings.original_bytes(&1.id), 1))) == [
             "%PDF-one",
             "%PDF-two"
           ]
  end

  test "failed downloads record their reason and HTTP status while retaining prior data" do
    assert {:ok, _} = HTTPHistory.record(attrs("prior", :success, "%PDF-first"))

    cases = [
      {:too_large, nil, %{}, false},
      {:too_large, 200, %{"content-length" => "99999999"}, false},
      {:interrupted, nil, %{}, true},
      {:timeout, nil, %{}, true},
      {:transport_error, nil, %{}, true},
      {:non_pdf, 200, %{}, false},
      {:unsupported_encoding, 200, %{"content-encoding" => "gzip"}, false},
      {:redirect_limit, 302, %{"location" => @final}, false},
      {:invalid_redirect, 301, %{}, false},
      {:url_not_allowed, nil, %{}, false},
      {:http_error, 404, %{}, false},
      {:http_error, 429, %{}, true},
      {:http_error, 503, %{"retry-after" => "60"}, true}
    ]

    for {reason, status, headers, retryable} <- cases do
      input = attrs("#{reason}-#{status}", :failed, nil)
      input = put_in(input.result.failure_reason, reason)
      input = put_in(input.result.http_status, status)
      input = put_in(input.result.headers, headers)
      input = put_in(input.result.retryable, retryable)
      assert {:ok, check} = HTTPHistory.record(input)
      assert check.failure_reason == to_string(reason)
      assert check.http_status == status
      assert check.response_headers == headers
      assert check.sha256 == nil
      assert Repo.get!(Acquisition, check.acquisition_id).status == "failed"
    end

    assert Repo.aggregate(Original, :count) == 1
    original = Repo.one!(Original)
    assert Earnings.original_bytes(original.id) == {:ok, "%PDF-first"}
  end

  test "persistence retries reuse one check, conflicts roll back instead of changing facts" do
    input = attrs("retry", :success, "%PDF-first")
    assert {:ok, first} = HTTPHistory.record(input)
    assert {:ok, second} = HTTPHistory.record(input)
    assert first == second

    assert {:error, :check_conflict} =
             HTTPHistory.record(Map.put(input, :published_on, ~D[2026-07-30]))

    assert Repo.aggregate(HTTPCheck, :count) == 1
    assert Repo.aggregate(Acquisition, :count) == 1
  end

  test "JSON-backed atom keys and values survive insertion and persistence retries" do
    input =
      attrs("json", :success, "%PDF-first")
      |> Map.put(:metadata, %{
        listing: %{label: :pending},
        dates: [~D[2026-07-29]],
        escaped_nul: "\\u0000"
      })
      |> put_in([:result, :headers], %{etag: "v1"})

    assert {:ok, check} = HTTPHistory.record(input)

    assert check.metadata == %{
             "listing" => %{"label" => "pending"},
             "dates" => ["2026-07-29"],
             "escaped_nul" => "\\u0000"
           }

    assert check.response_headers == %{"etag" => "v1"}
    assert {:ok, ^check} = HTTPHistory.record(input)
    assert Repo.aggregate(HTTPCheck, :count) == 1
    assert Repo.aggregate(Acquisition, :count) == 1
  end

  test "ambiguous releases retain partial metadata and later confirmation leaves check facts intact" do
    input = attrs("pending", :success, "%PDF-first") |> Map.delete(:release)

    input =
      Map.put(input, :metadata, %{
        "identity_status" => "pending_confirmation",
        "listing_label" => "FY2026"
      })

    assert {:ok, check} = HTTPHistory.record(input)
    acquisition = Repo.get!(Acquisition, check.acquisition_id)
    assert acquisition.release_id == nil
    assert check.published_on == nil

    assert {:ok, _} =
             Earnings.confirm_identity(acquisition.acquisition_id, %{
               fiscal_year_end: ~D[2027-03-31],
               period: "q1",
               category: "earnings_release"
             })

    assert Repo.get!(HTTPCheck, check.id) == check
  end

  test "listing checks and rejected-before-request outcomes create no PDF acquisitions" do
    assert {:ok, listing} =
             HTTPHistory.record(
               attrs("listing", :success, "<html>listing</html>")
               |> Map.put(:kind, :listing)
             )

    assert listing.acquisition_id == nil
    assert listing.byte_size > 0

    input =
      attrs("disabled", :failed, nil)
      |> put_in([:result, :requests], 0)
      |> put_in([:result, :failure_reason], :url_not_allowed)
      |> put_in([:result, :retryable], false)
      |> put_in([:result, :http_status], nil)
      |> put_in([:result, :headers], %{})

    assert {:ok, rejected} = HTTPHistory.record(input)
    assert rejected.acquisition_id == nil
    assert Repo.aggregate(Acquisition, :count) == 0
    assert Repo.aggregate(Original, :count) == 0
  end

  test "invalid result and oversized metadata cause no partial acquisitions" do
    input =
      attrs("bad", :success, "%PDF-first")
      |> Map.put(:metadata, %{"large" => String.duplicate("x", 32_769)})

    assert {:error, _} = HTTPHistory.record(input)

    assert {:error, _} =
             HTTPHistory.record(
               put_in(attrs("status", :success, "%PDF-first"), [:result, :http_status], 304)
             )

    assert Repo.aggregate(Acquisition, :count) == 0
    assert Repo.aggregate(Original, :count) == 0
  end

  test "explicit null JSON fields return validation errors without partial records" do
    for input <- [
          attrs("null-metadata", :success, "%PDF-first") |> Map.put(:metadata, nil),
          put_in(attrs("null-headers", :success, "%PDF-first"), [:result, :headers], nil)
        ] do
      assert {:error, %Ecto.Changeset{valid?: false}} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
    assert Repo.aggregate(Original, :count) == 0
  end

  test "NUL in JSON keys or nested strings is rejected before PostgreSQL insertion" do
    for input <- [
          attrs("nul-value", :success, "%PDF-first")
          |> Map.put(:metadata, %{"nested" => ["a\0b"]}),
          attrs("nul-key", :success, "%PDF-first") |> Map.put(:metadata, %{"a\0b" => "value"}),
          put_in(attrs("nul-header", :success, "%PDF-first"), [:result, :headers], %{
            "etag" => "a\0b"
          })
        ] do
      assert {:error, %Ecto.Changeset{valid?: false}} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
    assert Repo.aggregate(Original, :count) == 0
  end

  test "NUL in scalar HTTP facts is rejected before acquisition or check insertion" do
    inputs = [
      attrs("nul-check-id", :success, "%PDF-first") |> Map.put(:check_id, "bad\0id"),
      put_in(attrs("nul-failure", :failed, nil), [:result, :failure_reason], "bad\0reason"),
      attrs("nul-url", :failed, nil) |> Map.put(:url, "https://example.test/bad\0.pdf")
    ]

    for input <- inputs do
      assert {:error, %Ecto.Changeset{valid?: false}} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
    assert Repo.aggregate(Original, :count) == 0
  end

  test "database rejects rewriting or deleting completed check facts" do
    assert {:ok, check} = HTTPHistory.record(attrs("immutable", :success, "%PDF-first"))

    for sql <- [
          "UPDATE earnings_http_checks SET published_on = '2000-01-01' WHERE id = $1",
          "DELETE FROM earnings_http_checks WHERE id = $1"
        ] do
      assert_raise Postgrex.Error, ~r/immutable/, fn ->
        Repo.transaction(fn -> Repo.query!(sql, [Ecto.UUID.dump!(check.id)]) end,
          mode: :savepoint
        )
      end
    end

    assert Repo.get!(HTTPCheck, check.id) == check
  end

  test "malformed transport facts and failed identity writes leave no partial records" do
    inputs = [
      %{},
      attrs("missing", :success, nil),
      attrs("unexpected", :failed, "discard me"),
      attrs("marker", :success, "not a PDF") |> Map.put(:kind, "pdf"),
      put_in(attrs("outcome", :success, "%PDF-first"), [:result, :outcome], :unknown),
      put_in(attrs("url", :success, "%PDF-first"), [:url], "https://user:secret@example.test"),
      attrs("identity", :success, "%PDF-first") |> Map.put(:release, %{period: "invalid"}),
      put_in(attrs("zero-status", :failed, nil), [:result, :requests], 0)
      |> put_in([:result, :headers], %{}),
      put_in(attrs("zero-header", :failed, nil), [:result, :requests], 0)
      |> put_in([:result, :http_status], nil)
      |> put_in([:result, :headers], %{"etag" => "impossible"})
    ]

    for input <- inputs, do: assert({:error, _} = HTTPHistory.record(input))
    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
    assert Repo.aggregate(Original, :count) == 0
  end

  test "database rejects a check digest that disagrees with its retained original" do
    assert {:ok, check} = HTTPHistory.record(attrs("digest", :success, "%PDF-first"))

    sql = """
    INSERT INTO earnings_http_checks
      (id, check_id, issuer_code, kind, url, final_url, checked_at, published_on,
       status, failure_reason, http_status, requests, retryable, response_headers,
       metadata, sha256, byte_size, acquisition_id, inserted_at)
    SELECT $1, check_id, issuer_code, kind, url, final_url, checked_at, published_on,
       status, failure_reason, http_status, requests, retryable, response_headers,
       metadata, $2, byte_size, acquisition_id, inserted_at
    FROM earnings_http_checks WHERE id = $3
    """

    assert_raise Postgrex.Error, ~r/facts do not match/, fn ->
      Repo.transaction(
        fn ->
          Repo.query!(sql, [
            Ecto.UUID.dump!(Ecto.UUID.generate()),
            String.duplicate("0", 64),
            Ecto.UUID.dump!(check.id)
          ])
        end,
        mode: :savepoint
      )
    end

    assert Repo.aggregate(HTTPCheck, :count) == 1
  end

  defp redirect_server(target) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    pid =
      spawn(fn ->
        with {:ok, socket} <- :gen_tcp.accept(listener, 1000),
             {:ok, _request} <- :gen_tcp.recv(socket, 0, 1000) do
          :gen_tcp.send(
            socket,
            "HTTP/1.1 302 Found\r\nLocation: #{target}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
          )

          :gen_tcp.close(socket)
        end
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(pid, :kill)
    end)

    "http://127.0.0.1:#{port}/"
  end

  defp attrs(id, outcome, bytes) do
    status = %{success: 200, not_modified: 304, failed: 503}[outcome]

    %{
      check_id: id,
      issuer_code: "6857",
      url: @url,
      checked_at: @at,
      release: %{fiscal_year_end: ~D[2027-03-31], period: "q1", category: "earnings_release"},
      result: %{
        outcome: outcome,
        failure_reason: if(outcome == :failed, do: :http_error),
        bytes: bytes,
        http_status: status,
        final_url: @final,
        requests: 1,
        headers: %{"etag" => "v1"},
        retryable: outcome == :failed
      }
    }
  end
end
