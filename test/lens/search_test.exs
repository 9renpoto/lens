defmodule Lens.SearchTest do
  use Lens.DataCase

  alias Lens.{Content, Search}

  describe "search/2" do
    test "finds title and content matches, with title matches ranked first" do
      source = source_fixture()

      title_match = document_fixture(source, %{title: "Observatory notes", content: "A journal."})

      content_match =
        document_fixture(source, %{title: "Journal", content: "Notes from the observatory."})

      assert {:ok, results} = Search.search("observatory")

      assert Enum.map(results, & &1.id) == [title_match.id, content_match.id]
      assert Enum.all?(results, &(&1.excerpt != ""))
    end

    test "searches the latest canonical document content" do
      source = source_fixture()

      document =
        document_fixture(source, %{
          canonical_url: "https://example.com/documents/latest",
          title: "Update",
          content: "obsolete-term"
        })

      assert {:ok, %{document: updated_document}} =
               Content.observe_document(source, %{
                 canonical_url: document.canonical_url,
                 title: "Update",
                 content: "current-term"
               })

      assert updated_document.id == document.id
      assert {:ok, []} = Search.search("obsolete-term")
      assert {:ok, [%{id: document_id}]} = Search.search("current-term")
      assert document_id == document.id
    end

    test "paginates stable search results by rank and document ID" do
      source = source_fixture()

      first = document_fixture(source, %{title: "Pagination", content: "same rank"})
      second = document_fixture(source, %{title: "Pagination", content: "same rank"})

      assert {:ok, [first_result]} = Search.search("pagination", limit: 1, offset: 0)
      assert {:ok, [second_result]} = Search.search("pagination", limit: 1, offset: 1)

      assert [first_result.id, second_result.id] == Enum.sort([first.id, second.id])
    end

    test "returns no results for terms that are not indexed" do
      assert {:ok, []} = Search.search("absent-term")
    end

    test "rebuilds derived search data from canonical documents" do
      source = source_fixture()
      document_fixture(source, %{title: "Rebuild", content: "rebuildable-term"})

      assert :ok = Search.rebuild(batch_size: 1)
      assert {:ok, [%{title: "Rebuild"}]} = Search.search("rebuildable-term")
    end

    test "rejects an invalid rebuild batch size" do
      assert {:error, :invalid_batch_size} = Search.rebuild(batch_size: 0)
    end

    test "rejects empty and oversized queries and invalid pagination" do
      assert {:error, :invalid_query} = Search.search("  ")
      assert {:error, :invalid_query} = Search.search(String.duplicate("a", 501))
      assert {:error, :invalid_pagination} = Search.search("term", limit: 0)
      assert {:error, :invalid_pagination} = Search.search("term", limit: 101)
      assert {:error, :invalid_pagination} = Search.search("term", offset: -1)
    end

    test "treats query syntax as data" do
      assert {:ok, []} = Search.search("' OR true --")
    end
  end

  defp source_fixture do
    {:ok, source} =
      Content.create_source(%{
        source_type: "rss",
        endpoint_url: "https://feeds.example.com/#{System.unique_integer([:positive])}.xml",
        poll_interval_seconds: 300
      })

    source
  end

  defp document_fixture(source, attrs) do
    defaults = %{
      canonical_url: "https://example.com/documents/#{System.unique_integer([:positive])}",
      title: "Document",
      content: "Content"
    }

    {:ok, %{document: document}} = Content.observe_document(source, Map.merge(defaults, attrs))
    document
  end
end
