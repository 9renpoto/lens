defmodule LensWeb.ApiSchemas do
  @moduledoc false

  alias OpenApiSpex.Schema

  defmodule HealthResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "HealthResponse",
      type: :object,
      properties: %{status: %Schema{type: :string, enum: ["ok"]}},
      required: [:status]
    })
  end

  defmodule ReadyResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ReadyResponse",
      type: :object,
      properties: %{status: %Schema{type: :string, enum: ["ready"]}},
      required: [:status]
    })
  end

  defmodule UnavailableResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UnavailableResponse",
      type: :object,
      properties: %{status: %Schema{type: :string, enum: ["unavailable"]}},
      required: [:status]
    })
  end

  defmodule ErrorResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      type: :object,
      properties: %{error: %Schema{type: :string}},
      required: [:error]
    })
  end

  defmodule ValidationErrorsResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ValidationErrorsResponse",
      type: :object,
      properties: %{
        errors: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}
        }
      },
      required: [:errors]
    })
  end

  defmodule SourceAttributes do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SourceAttributes",
      type: :object,
      properties: %{
        source_type: %Schema{type: :string, enum: ["rss", "atom", "rsshub"]},
        endpoint_url: %Schema{type: :string, format: :uri},
        title: %Schema{type: :string, maxLength: 1_000},
        enabled: %Schema{type: :boolean},
        poll_interval_seconds: %Schema{type: :integer, minimum: 1},
        metadata: %Schema{type: :object}
      }
    })
  end

  defmodule CreateSourceRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CreateSourceRequest",
      type: :object,
      properties: %{source: SourceAttributes},
      required: [:source]
    })
  end

  defmodule UpdateSourceRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UpdateSourceRequest",
      type: :object,
      properties: %{source: SourceAttributes}
    })
  end

  defmodule Source do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Source",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        source_type: %Schema{type: :string, enum: ["rss", "atom", "rsshub"]},
        endpoint_url: %Schema{type: :string, format: :uri},
        title: %Schema{type: :string, nullable: true},
        enabled: %Schema{type: :boolean},
        poll_interval_seconds: %Schema{type: :integer, minimum: 1},
        next_fetch_at: %Schema{type: :string, format: :"date-time"},
        last_attempt_at: %Schema{type: :string, format: :"date-time", nullable: true},
        last_success_at: %Schema{type: :string, format: :"date-time", nullable: true},
        last_error: %Schema{type: :string, nullable: true},
        failure_count: %Schema{type: :integer, minimum: 0}
      },
      required: [
        :id,
        :source_type,
        :endpoint_url,
        :enabled,
        :poll_interval_seconds,
        :next_fetch_at,
        :failure_count
      ]
    })
  end

  defmodule SourceResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SourceResponse",
      type: :object,
      properties: %{source: Source},
      required: [:source]
    })
  end

  defmodule SourcesResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SourcesResponse",
      type: :object,
      properties: %{sources: %Schema{type: :array, items: Source}},
      required: [:sources]
    })
  end

  defmodule SearchResult do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SearchResult",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        title: %Schema{type: :string, nullable: true},
        canonical_url: %Schema{type: :string, format: :uri, nullable: true},
        published_at: %Schema{type: :string, format: :"date-time", nullable: true},
        excerpt: %Schema{type: :string, maxLength: 300}
      },
      required: [:id, :excerpt]
    })
  end

  defmodule SearchResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SearchResponse",
      type: :object,
      properties: %{results: %Schema{type: :array, items: SearchResult}},
      required: [:results]
    })
  end

  defmodule Document do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Document",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        title: %Schema{type: :string, nullable: true},
        canonical_url: %Schema{type: :string, format: :uri, nullable: true},
        content: %Schema{type: :string},
        author: %Schema{type: :string, nullable: true},
        published_at: %Schema{type: :string, format: :"date-time", nullable: true},
        metadata: %Schema{type: :object},
        sources: %Schema{type: :array, items: LensWeb.ApiSchemas.SourceProvenance}
      },
      required: [:id, :content, :metadata, :sources]
    })
  end

  defmodule SourceProvenance do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SourceProvenance",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        source_type: %Schema{type: :string, enum: ["rss", "atom", "rsshub"]},
        endpoint_url: %Schema{type: :string, format: :uri},
        observed_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :source_type, :endpoint_url, :observed_at]
    })
  end

  defmodule DocumentResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DocumentResponse",
      type: :object,
      properties: %{document: Document},
      required: [:document]
    })
  end
end
