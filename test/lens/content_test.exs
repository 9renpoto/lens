defmodule Lens.ContentTest do
  use Lens.DataCase

  alias Lens.Content
  alias Lens.Content.{Document, Identity}

  describe "sources" do
    test "validates source scheduling and endpoint configuration" do
      assert {:error, changeset} =
               Content.create_source(%{
                 source_type: "rss",
                 endpoint_url: "not a URL",
                 poll_interval_seconds: 0
               })

      assert %{endpoint_url: ["must be an absolute HTTP(S) URL without credentials"]} =
               errors_on(changeset)

      assert %{poll_interval_seconds: ["must be greater than 0"]} = errors_on(changeset)
    end
  end

  describe "observe_document/3" do
    test "records repeated observations without duplicating the document" do
      source = source_fixture()

      attrs = %{
        canonical_url: "HTTPS://Example.COM:443/articles/lens?edition=1#section",
        title: "Lens",
        content: "First paragraph\n\nSecond paragraph",
        published_at: ~U[2026-09-07 00:00:00.000000Z]
      }

      assert {:ok, %{document: first_document}} =
               Content.observe_document(source, attrs,
                 observed_at: ~U[2026-09-07 01:00:00.000000Z]
               )

      assert {:ok, %{document: second_document}} =
               Content.observe_document(source, attrs,
                 observed_at: ~U[2026-09-07 02:00:00.000000Z]
               )

      assert first_document.id == second_document.id
      assert first_document.canonical_url == "https://example.com/articles/lens?edition=1"
      assert Repo.aggregate(Document, :count) == 1
      assert Content.list_observations(first_document) |> length() == 2
    end

    test "shares canonical URLs across sources and keeps the latest content" do
      first_source = source_fixture(endpoint_url: "https://feeds.example.com/first.xml")
      second_source = source_fixture(endpoint_url: "https://feeds.example.com/second.xml")

      assert {:ok, %{document: first_document}} =
               Content.observe_document(first_source, %{
                 canonical_url: "https://example.com/posts/1",
                 title: "Post",
                 content: "Original content"
               })

      assert {:ok, %{document: second_document}} =
               Content.observe_document(second_source, %{
                 canonical_url: "https://example.com/posts/1",
                 title: "Post",
                 content: "Updated content"
               })

      assert first_document.id == second_document.id
      assert Repo.aggregate(Document, :count) == 1
      assert Content.get_document!(first_document.id).content == "Updated content"

      observations = Content.list_observations(first_document)
      assert length(observations) == 2

      assert Enum.map(observations, & &1.content_hash) == [
               second_document.content_hash,
               first_document.content_hash
             ]
    end

    test "preserves known optional values when a later observation omits them" do
      source = source_fixture()

      assert {:ok, %{document: document}} =
               Content.observe_document(source, %{
                 canonical_url: "https://example.com/posts/2",
                 title: "Original title",
                 content: "Original content",
                 author: "Ada",
                 published_at: ~U[2026-09-06 00:00:00.000000Z],
                 metadata: %{"topic" => "elixir"}
               })

      assert {:ok, %{document: updated_document}} =
               Content.observe_document(source, %{
                 canonical_url: "https://example.com/posts/2",
                 content: "Updated content",
                 metadata: %{"language" => "en"}
               })

      assert updated_document.id == document.id
      assert updated_document.title == "Original title"
      assert updated_document.author == "Ada"
      assert updated_document.published_at == ~U[2026-09-06 00:00:00.000000Z]
      assert updated_document.metadata == %{"language" => "en", "topic" => "elixir"}
      assert updated_document.content == "Updated content"
      refute updated_document.content_hash == document.content_hash
    end

    test "retains documents when their source is disabled" do
      source = source_fixture()

      assert {:ok, %{document: document}} =
               Content.observe_document(source, %{
                 canonical_url: "https://example.com/posts/retained",
                 title: "Retained",
                 content: "Content"
               })

      assert {:ok, disabled_source} = Content.update_source(source, %{enabled: false})
      refute disabled_source.enabled
      assert Content.get_document!(document.id).content == "Content"
    end

    test "uses source-scoped entry IDs and a source-scoped fallback identity" do
      first_source = source_fixture(endpoint_url: "https://feeds.example.com/one.xml")
      second_source = source_fixture(endpoint_url: "https://feeds.example.com/two.xml")

      assert {:ok, %{document: entry_document}} =
               Content.observe_document(first_source, %{
                 source_entry_id: "entry-1",
                 title: "Entry",
                 content: "Content"
               })

      assert {:ok, %{document: fallback_document}} =
               Content.observe_document(second_source, %{title: "Entry", content: "Content"})

      assert String.starts_with?(entry_document.identity_key, "entry:#{first_source.id}:entry-1")
      assert String.starts_with?(fallback_document.identity_key, "fallback:#{second_source.id}:")
      assert entry_document.id != fallback_document.id
    end

    test "keeps one document during concurrent upserts" do
      source = source_fixture()

      attrs = %{
        canonical_url: "https://example.com/posts/concurrent",
        title: "Concurrent",
        content: "Content"
      }

      results =
        1..2
        |> Task.async_stream(
          fn index ->
            Content.observe_document(source, attrs,
              observed_at: DateTime.add(~U[2026-09-07 03:00:00.000000Z], index, :second)
            )
          end,
          max_concurrency: 2,
          timeout: 5_000
        )
        |> Enum.to_list()

      assert Enum.all?(results, fn
               {:ok, {:ok, _result}} -> true
               _ -> false
             end)

      assert Repo.aggregate(Document, :count) == 1

      [document] = Repo.all(Document)
      assert Content.list_observations(document) |> length() == 2
    end

    test "rolls back the document when its observation cannot be stored" do
      source_id = Ecto.UUID.generate()

      attrs = %{
        canonical_url: "https://example.com/posts/rollback",
        title: "Rollback",
        content: "Content"
      }

      identity_key = Identity.normalize_entry(source_id, attrs).identity_key

      assert {:error, _changeset} = Content.observe_document(source_id, attrs)
      assert Repo.get_by(Document, identity_key: identity_key) == nil
    end
  end

  describe "scheduled sources" do
    test "claims a due source once and schedules its next fetch" do
      now = ~U[2026-09-08 00:00:00Z]
      source = source_fixture(next_fetch_at: DateTime.add(now, -1, :second))

      assert [source.id] == Content.claim_due_sources(now, 2)
      assert [] == Content.claim_due_sources(now, 2)

      assert {:ok, updated_source} =
               Content.schedule_next_fetch(
                 source.id,
                 %Lens.Ingestion.Result{outcome: :success},
                 now
               )

      assert DateTime.compare(updated_source.next_fetch_at, DateTime.add(now, 300, :second)) ==
               :eq
    end

    test "clears validators and makes a changed endpoint immediately due" do
      source =
        source_fixture(
          etag: "v1",
          last_modified: "yesterday",
          next_fetch_at: ~U[2026-09-09 00:00:00Z]
        )

      assert {:ok, updated} =
               Content.update_source(source, %{
                 endpoint_url: "https://feeds.example.com/updated.xml"
               })

      assert updated.etag == nil
      assert updated.last_modified == nil
      assert updated.next_fetch_at
    end
  end

  defp source_fixture(attrs \\ %{}) do
    attributes =
      Map.merge(
        %{
          source_type: "rss",
          endpoint_url: "https://feeds.example.com/default.xml",
          poll_interval_seconds: 300
        },
        Map.new(attrs)
      )

    {:ok, source} = Content.create_source(attributes)
    source
  end
end
