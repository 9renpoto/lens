defmodule Lens.Earnings.HTTPHistoryTest do
  use Lens.DataCase
  alias Lens.Earnings
  alias Lens.Earnings.{Acquisition, HTTP, HTTPHistory, HTTPCheck, Original}

  @at ~U[2026-10-02 00:00:00.000000Z]
  @url "https://example.test/request.pdf"
  @final "https://example.test/actual.pdf"

  test "records listing and PDF checks for issuers outside the former pilot without registration" do
    for {kind, body} <- [{:listing, "<html>listing</html>"}, {:pdf, "%PDF-non-pilot"}] do
      input =
        attrs("non-pilot-#{kind}", :success, body)
        |> Map.put(:issuer_code, "7203")
        |> Map.put(:kind, kind)
        |> Map.delete(:release)

      assert {:ok, check} = HTTPHistory.record(input)
      assert check.issuer_code == "7203"
      assert {:ok, ^check} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 2
    assert Repo.aggregate(Acquisition, :count) == 1
  end

  test "database bounds permit non-pilot listing issuers while still enforcing response bounds" do
    input =
      attrs("listing-bounds", :success, "<html>listing</html>")
      |> Map.put(:kind, :listing)
      |> Map.delete(:release)

    assert {:ok, check} = HTTPHistory.record(input)
    assert {1, nil} = Repo.insert_all(HTTPCheck, [copied_row(check, %{issuer_code: "7203"})])
    assert_db_rejects(check, %{issuer_code: "7203", requests: 5}, :check_violation)
  end

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

  test "response-level size failures need evidence while small configured limits remain valid" do
    for {headers, index} <-
          Enum.with_index([
            %{},
            %{"content-length" => nil},
            %{"content-length" => "unknown"},
            %{"content-length" => "2 bytes"},
            %{"content-length" => "0"},
            %{"content-length" => "1"},
            %{"content-length" => "-2"},
            %{"content-length" => <<255>>}
          ]) do
      input =
        attrs("size-evidence-#{index}", :failed, nil)
        |> put_in([:result, :failure_reason], :too_large)
        |> put_in([:result, :http_status], 200)
        |> put_in([:result, :headers], headers)
        |> put_in([:result, :retryable], false)

      assert {:error, %Ecto.Changeset{valid?: false}} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0

    url = response_server("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nab")
    result = HTTP.fetch(url, allowed_url?: &(&1 == url), max_bytes: 1)
    assert result.failure_reason == :too_large
    assert result.http_status == 200

    input = attrs("small-limit", :failed, nil) |> Map.put(:url, url) |> Map.put(:result, result)
    assert {:ok, check} = HTTPHistory.record(input)
    assert check.response_headers["content-length"] == "2"
    assert check.byte_size == nil
    assert Repo.aggregate(Original, :count) == 0
  end

  test "response failure facts respect size and encoding checks before PDF classification" do
    for {reason, headers} <- [
          {:non_pdf, %{"content-encoding" => "gzip"}},
          {:non_pdf, %{"content-length" => "20971521"}},
          {:unsupported_encoding, %{"content-length" => "20971521", "content-encoding" => "gzip"}}
        ] do
      input =
        attrs("response-priority-#{reason}-#{inspect(headers)}", :failed, nil)
        |> put_in([:result, :failure_reason], reason)
        |> put_in([:result, :http_status], 200)
        |> put_in([:result, :headers], headers)
        |> put_in([:result, :retryable], false)

      assert {:error, %Ecto.Changeset{valid?: false}} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "successful PDF and listing checks reject contradictory response headers" do
    for {kind, bytes, cap} <- [
          {:pdf, "%PDF-valid", 20_971_520},
          {:listing, "<html>valid</html>", 2_097_152}
        ],
        headers <- [
          %{"content-encoding" => "gzip"},
          %{"content-encoding" => "identity, gzip"},
          %{"content-encoding" => <<255>>},
          %{"content-length" => Integer.to_string(cap + 1)}
        ] do
      input =
        attrs("success-#{kind}-#{inspect(headers)}", :success, bytes) |> Map.put(:kind, kind)

      input = put_in(input, [:result, :headers], headers)
      assert {:error, %Ecto.Changeset{valid?: false}} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
    assert Repo.aggregate(Original, :count) == 0
  end

  test "invalid redirects require missing or unresolvable location evidence" do
    for location <- [
          "https://example.test/next",
          "/next",
          "../next",
          "",
          "mailto:test@example.com"
        ] do
      input = attrs("resolvable-#{location}", :failed, nil)

      result = %{
        input.result
        | failure_reason: :invalid_redirect,
          http_status: 302,
          headers: %{"location" => location},
          retryable: false
      }

      assert {:error, %Ecto.Changeset{valid?: false}} =
               HTTPHistory.record(%{input | result: result})
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "legitimate header boundaries and redirect-limit results remain accepted" do
    for {id, outcome, bytes, headers} <- [
          {"success-identity", :success, "%PDF-valid",
           %{"content-encoding" => "Identity, identity", "content-length" => "20971520"}},
          {"success-unknown-length", :success, "%PDF-valid", %{"content-length" => "unknown"}},
          {"success-no-headers", :success, "%PDF-valid", %{}},
          {"304-unchecked-headers", :not_modified, nil,
           %{"content-encoding" => "gzip", "content-length" => "999999999"}}
        ] do
      input = put_in(attrs(id, outcome, bytes), [:result, :headers], headers)
      assert {:ok, check} = HTTPHistory.record(input)
      assert {:ok, ^check} = HTTPHistory.record(input)
    end

    for {reason, headers} <- [
          {:invalid_redirect, %{}},
          {:invalid_redirect, %{"location" => "http://["}},
          {:invalid_redirect, %{"location" => <<255>>}},
          {:redirect_limit, %{}},
          {:redirect_limit, %{"location" => "/next"}}
        ] do
      input = attrs("allowed-#{reason}-#{inspect(headers)}", :failed, nil)

      result = %{
        input.result
        | failure_reason: reason,
          http_status: 302,
          headers: headers,
          retryable: false
      }

      assert {:ok, check} = HTTPHistory.record(%{input | result: result})
      assert {:ok, ^check} = HTTPHistory.record(%{input | result: result})
    end
  end

  test "a worker exit before dialing retains history without an acquisition" do
    input = attrs("interrupted-before-dialing", :failed, nil)

    result = HTTP.fetch(@url, allowed_url?: fn _ -> Process.exit(self(), :kill) end)
    assert result.failure_reason == :transport_error
    assert result.requests == 0

    assert {:ok, check} = HTTPHistory.record(%{input | result: result})
    assert check.acquisition_id == nil
    assert check.requests == 0
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "an interrupted response requires a started request" do
    input = attrs("interrupted-before-dialing", :failed, nil)

    result = %{
      input.result
      | failure_reason: :interrupted,
        requests: 0,
        http_status: nil,
        headers: %{},
        retryable: true
    }

    assert {:error, %Ecto.Changeset{valid?: false}} =
             HTTPHistory.record(%{input | result: result})

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
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

  test "timeout and interruption retain an evaluated non-HTTP redirect target" do
    target = "mailto:test@example.com"
    url = redirect_server(target)
    denied = HTTP.fetch(url, allowed_url?: &(&1 == url))
    assert denied.failure_reason == :url_not_allowed
    assert denied.final_url == target

    for reason <- [:timeout, :interrupted] do
      result = %{denied | failure_reason: reason, retryable: true}

      input =
        attrs("redirect-#{reason}", :failed, nil)
        |> Map.put(:url, url)
        |> Map.put(:result, result)

      assert {:ok, check} = HTTPHistory.record(input)
      assert check.final_url == target
      assert check.requests == 1
      assert check.http_status == nil
      assert check.response_headers == %{}
      acquisition = Repo.get!(Acquisition, check.acquisition_id)
      assert acquisition.url == url
      assert acquisition.failure_reason == Atom.to_string(reason)
      assert {:ok, ^check} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 2
    assert Repo.aggregate(Acquisition, :count) == 2
    assert Repo.aggregate(Original, :count) == 0
  end

  test "zero-request failures require the evaluated URL before retaining immutable facts" do
    results = [
      HTTP.fetch(@url, max_bytes: 0),
      HTTP.fetch(@url, deadline: System.monotonic_time(:millisecond) - 1),
      HTTP.fetch(@url)
    ]

    for result <- results do
      assert result.requests == 0
      input = attrs("missing-evaluated-#{result.failure_reason}", :failed, nil)
      input = Map.put(input, :result, Map.delete(result, :final_url))
      assert {:error, %Ecto.Changeset{valid?: false}} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0

    for result <- results do
      input = attrs("evaluated-#{result.failure_reason}", :failed, nil)
      assert {:ok, check} = HTTPHistory.record(Map.put(input, :result, result))
      assert check.final_url == @url
      assert check.requests == 0
      assert check.acquisition_id == nil
    end

    assert Repo.aggregate(HTTPCheck, :count) == 3
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "non-UTF-8 HTTP response header bytes survive persistence and retries exactly" do
    raw = <<255>>

    inputs =
      for {field, status, body, outcome, reason} <- [
            {"location", 302, "", :failed, :invalid_redirect},
            {"etag", 200, "%PDF-original", :success, nil},
            {"content-encoding", 200, "%PDF-unused", :failed, :unsupported_encoding}
          ] do
        url =
          response_server(
            "HTTP/1.1 #{status} OK\r\n#{field}: #{raw}\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n#{body}"
          )

        result = HTTP.fetch(url, allowed_url?: &(&1 == url))
        assert result.outcome == outcome
        assert result.failure_reason == reason
        assert result.headers[field] == raw

        input =
          attrs("binary-header-#{field}", outcome, result.bytes)
          |> Map.put(:url, url)
          |> Map.put(:result, result)

        {field, input}
      end

    for {field, input} <- inputs do
      assert {:ok, check} = HTTPHistory.record(input)
      assert check.response_headers[field] == %{"encoding" => "base64", "value" => "/w=="}
      assert Base.decode64!(check.response_headers[field]["value"]) == raw
      assert {:ok, ^check} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 3
    assert Repo.aggregate(Acquisition, :count) == 3
    assert Repo.aggregate(Original, :count) == 1
  end

  test "unsupported encoding failures require header evidence after JSON normalization" do
    for {headers, index} <-
          Enum.with_index([
            %{},
            %{"content-encoding" => nil},
            %{"content-encoding" => ["gzip"]},
            %{"content-encoding" => %{"encoding" => "base64", "value" => "aWRlbnRpdHk="}},
            %{"content-encoding" => %{"encoding" => "base64", "value" => "not base64"}},
            %{"content-encoding" => "identity"},
            %{"content-encoding" => " Identity , IDENTITY "},
            %{:"content-encoding" => :identity}
          ]) do
      input =
        attrs("unsupported-identity-#{index}", :failed, nil)
        |> put_in([:result, :failure_reason], :unsupported_encoding)
        |> put_in([:result, :http_status], 200)
        |> put_in([:result, :headers], headers)
        |> put_in([:result, :retryable], false)

      assert {:error, %Ecto.Changeset{valid?: false}} = HTTPHistory.record(input)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0

    for {headers, index} <-
          Enum.with_index([
            %{"content-encoding" => "gzip"},
            %{"content-encoding" => "identity, GZip"},
            %{:"content-encoding" => :gzip}
          ]) do
      input =
        attrs("unsupported-evidence-#{index}", :failed, nil)
        |> put_in([:result, :failure_reason], :unsupported_encoding)
        |> put_in([:result, :http_status], 200)
        |> put_in([:result, :headers], headers)
        |> put_in([:result, :retryable], false)

      assert {:ok, check} = HTTPHistory.record(input)
      assert check.failure_reason == "unsupported_encoding"
      assert check.response_headers == headers |> Jason.encode!() |> Jason.decode!()
      assert {:ok, ^check} = HTTPHistory.record(input)
    end
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
      |> put_in([:result, :final_url], @url)
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
          }),
          put_in(attrs("binary-nul-header", :success, "%PDF-first"), [:result, :headers], %{
            "etag" => <<255, 0>>
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

  test "zero-request results cannot claim a different evaluated URL" do
    for reason <- [:invalid_options, :url_not_allowed, :timeout, :transport_error] do
      input = attrs("zero-target-#{reason}", :failed, nil)

      result = %{
        input.result
        | requests: 0,
          failure_reason: reason,
          http_status: nil,
          headers: %{},
          retryable: reason in [:timeout, :transport_error]
      }

      assert {:error, %Ecto.Changeset{valid?: false}} =
               HTTPHistory.record(%{input | result: result})
    end

    assert Repo.aggregate(HTTPCheck, :count) == 0
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "database requires a final URL even when changesets are bypassed" do
    assert {:ok, check} = HTTPHistory.record(attrs("required-final", :not_modified, nil))
    assert_db_rejects(check, %{final_url: nil}, :not_null_violation)
    assert Repo.aggregate(HTTPCheck, :count) == 1
  end

  test "database requires zero-request URL and response consistency" do
    input = attrs("zero-db", :failed, nil)

    result = %{
      input.result
      | requests: 0,
        failure_reason: :timeout,
        final_url: @url,
        http_status: nil,
        headers: %{},
        retryable: true
    }

    assert {:ok, check} = HTTPHistory.record(%{input | result: result})

    for changes <- [
          %{final_url: @final},
          %{http_status: 503},
          %{response_headers: %{"etag" => "impossible"}}
        ] do
      assert_db_rejects(check, changes, :check_violation)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 1
  end

  test "database accepts valid structural facts through bulk insertion" do
    for {id, outcome, bytes} <- [
          {"bulk-success", :success, "listing"},
          {"bulk-304", :not_modified, nil},
          {"bulk-zero", :failed, nil}
        ] do
      input = attrs(id, outcome, bytes) |> Map.put(:kind, :listing)

      input =
        if outcome == :failed do
          %{
            input
            | result: %{
                input.result
                | failure_reason: :invalid_options,
                  final_url: @url,
                  http_status: nil,
                  requests: 0,
                  retryable: false,
                  headers: %{}
              }
          }
        else
          input
        end

      assert {:ok, check} = HTTPHistory.record(input)
      assert {1, nil} = Repo.insert_all(HTTPCheck, [copied_row(check, %{})])
    end

    assert Repo.aggregate(HTTPCheck, :count) == 6
    assert Repo.aggregate(Acquisition, :count) == 0
  end

  test "database forbids retryable success and not-modified checks" do
    for {id, outcome, bytes} <- [
          {"retry-db-success", :success, "listing"},
          {"retry-db-304", :not_modified, nil}
        ] do
      assert {:ok, check} =
               HTTPHistory.record(attrs(id, outcome, bytes) |> Map.put(:kind, :listing))

      assert_db_rejects(check, %{retryable: true}, :check_violation)
    end

    assert Repo.aggregate(HTTPCheck, :count) == 2
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

  defp assert_db_rejects(check, changes, code) do
    row = copied_row(check, changes)

    error =
      assert_raise Postgrex.Error, fn ->
        Repo.transaction(fn -> Repo.insert_all(HTTPCheck, [row]) end, mode: :savepoint)
      end

    assert error.postgres.code == code
  end

  defp copied_row(check, changes) do
    check
    |> Map.from_struct()
    |> Map.take(HTTPCheck.facts() ++ [:inserted_at])
    |> Map.merge(changes)
    |> Map.put(:id, Ecto.UUID.generate())
    |> Map.put(:check_id, Ecto.UUID.generate())
  end

  defp redirect_server(target) do
    response_server(
      "HTTP/1.1 302 Found\r\nLocation: #{target}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    )
  end

  defp response_server(response) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    pid =
      spawn(fn ->
        with {:ok, socket} <- :gen_tcp.accept(listener, 1000),
             {:ok, _request} <- :gen_tcp.recv(socket, 0, 1000) do
          :gen_tcp.send(socket, response)

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
