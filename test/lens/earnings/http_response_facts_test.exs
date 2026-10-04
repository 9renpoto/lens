defmodule Lens.Earnings.HTTPResponseFactsTest do
  use ExUnit.Case, async: true
  alias Lens.Earnings.HTTPResponseFacts, as: Facts

  test "raw and JSON-normalized headers carry the same evidence" do
    assert Facts.header_bytes(%{"etag" => <<255>>}, "etag") == {:ok, <<255>>}

    assert Facts.header_bytes(%{:"content-encoding" => :identity}, "content-encoding") ==
             {:ok, "identity"}

    assert Facts.header_bytes(%{"etag" => encoded(<<255>>)}, "etag") == {:ok, <<255>>}
    assert Facts.header_bytes(%{}, "missing", "default") == {:ok, "default"}
    assert Facts.header_bytes(%{"missing" => nil}, "missing", "default") == :error
    assert Facts.header_bytes(nil, "missing") == :error

    assert Facts.header_bytes(%{"etag" => %{"encoding" => "base64", "value" => "?"}}, "etag") ==
             :error

    assert Facts.header_bytes(%{"etag" => self()}, "etag") == :error
  end

  test "alias keys agree with the JSON representation used for persistence" do
    for headers <- [
          %{:"content-encoding" => "gzip", "content-encoding" => "identity"},
          %{:"content-encoding" => "identity", "content-encoding" => "gzip"}
        ] do
      canonical = headers |> Jason.encode!() |> Jason.decode!()

      assert Facts.header_bytes(headers, "content-encoding") ==
               Facts.header_bytes(canonical, "content-encoding")

      assert Facts.identity_encoding?(headers) == Facts.identity_encoding?(canonical)
    end
  end

  test "advertised size only causes overflow when a complete integer exceeds the given limit" do
    assert Facts.size_cap(:listing) == Facts.size_cap("listing")
    assert Facts.size_cap(:pdf) == 20_971_520
    assert Facts.oversized?(%{"content-length" => "2"}, 1)
    refute Facts.oversized?(%{"content-length" => "20971520"}, Facts.size_cap(:pdf))
    assert Facts.oversized?(%{"content-length" => encoded("20971521")}, Facts.size_cap(:pdf))

    for value <- [nil, "unknown", "2 bytes", <<255>>] do
      assert Facts.advertised_size(%{"content-length" => value}) == :error
      refute Facts.oversized?(%{"content-length" => value}, 1)
    end
  end

  test "identity encoding has the same meaning for raw and retained header bytes" do
    assert Facts.identity_encoding?(%{})
    assert Facts.identity_encoding?(%{"content-encoding" => " Identity , IDENTITY "})
    assert Facts.identity_encoding?(%{"content-encoding" => encoded("identity")})

    for value <- ["gzip", "identity, gzip", "", <<255>>, nil, ["identity"]] do
      refute Facts.identity_encoding?(%{"content-encoding" => value})
    end
  end

  test "redirect resolution is independent of URL permission" do
    base = "https://example.test/path/file.pdf"

    assert Facts.redirect_target(base, %{"location" => "../next"}) ==
             {:ok, "https://example.test/next"}

    assert Facts.redirect_target(base, %{"location" => ""}) == {:ok, base}

    assert Facts.redirect_target(base, %{"location" => "mailto:test@example.com"}) ==
             {:ok, "mailto:test@example.com"}

    assert Facts.redirect_target(base, %{"location" => encoded("/next")}) ==
             {:ok, "https://example.test/next"}

    for headers <- [
          %{},
          %{"location" => "http://["},
          %{"location" => <<255>>},
          %{"location" => encoded(<<255>>)}
        ] do
      assert Facts.redirect_target(base, headers) == :error
    end

    assert Facts.redirect_target(nil, %{"location" => "/next"}) == :error
  end

  defp encoded(value), do: %{"encoding" => "base64", "value" => Base.encode64(value)}
end
