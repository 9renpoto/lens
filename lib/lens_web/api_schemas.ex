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
        excerpt: %Schema{type: :string, maxLength: 300},
        provenance_url: %Schema{type: :string}
      },
      required: [:id, :excerpt, :provenance_url]
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
        sources: %Schema{type: :array, items: LensWeb.ApiSchemas.SourceProvenance},
        provenance_url: %Schema{type: :string}
      },
      required: [:id, :content, :metadata, :sources, :provenance_url]
    })
  end

  defmodule ObservationProvenance do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ObservationProvenance",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        source_id: %Schema{type: :string, format: :uuid},
        observed_at: %Schema{type: :string, format: :"date-time"},
        content_hash: %Schema{type: :string},
        entry_url: %Schema{type: :string, format: :uri, nullable: true},
        primary_source_url: %Schema{type: :string, format: :uri, nullable: true},
        feed_format: %Schema{type: :string, enum: ["rss_2_0", "atom", "rss_1_0", "unknown"]},
        acquisition_kind: %Schema{
          type: :string,
          enum: ["direct", "conversion_service", "rsshub", "unknown"]
        },
        publisher_authority: %Schema{
          type: :string,
          enum: ["official", "third_party", "unknown"]
        },
        acquisition_metadata_snapshot: %Schema{type: :object},
        reported_published_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [
        :id,
        :source_id,
        :observed_at,
        :content_hash,
        :feed_format,
        :acquisition_kind,
        :publisher_authority,
        :acquisition_metadata_snapshot
      ]
    })
  end

  defmodule DocumentProvenanceResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DocumentProvenanceResponse",
      type: :object,
      properties: %{
        observations: %Schema{
          type: :array,
          items: ObservationProvenance
        }
      },
      required: [:observations]
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

  defmodule MembershipAttributes do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "MembershipAttributes",
      type: :object,
      properties: %{
        index_name: %Schema{type: :string, default: "nikkei_225"},
        effective_from: %Schema{type: :string, format: :date},
        effective_to: %Schema{type: :string, format: :date, nullable: true},
        source_reference: %Schema{type: :string, maxLength: 1000, nullable: true},
        verified_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:effective_from]
    })
  end

  defmodule Membership do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Membership",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        target_id: %Schema{type: :string, format: :uuid},
        index_name: %Schema{type: :string},
        effective_from: %Schema{type: :string, format: :date},
        effective_to: %Schema{type: :string, format: :date, nullable: true},
        source_reference: %Schema{type: :string, maxLength: 1000, nullable: true},
        verified_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:id, :target_id, :index_name, :effective_from]
    })
  end

  defmodule CreateMembershipRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CreateMembershipRequest",
      type: :object,
      properties: %{membership: MembershipAttributes},
      required: [:membership]
    })
  end

  defmodule UpdateMembershipAttributes do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UpdateMembershipAttributes",
      type: :object,
      properties: %{
        effective_to: %Schema{type: :string, format: :date, nullable: true},
        source_reference: %Schema{type: :string, maxLength: 1000, nullable: true},
        verified_at: %Schema{type: :string, format: :"date-time", nullable: true}
      }
    })
  end

  defmodule UpdateMembershipRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UpdateMembershipRequest",
      type: :object,
      properties: %{membership: UpdateMembershipAttributes},
      required: [:membership]
    })
  end

  defmodule MembershipResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "MembershipResponse",
      type: :object,
      properties: %{membership: Membership},
      required: [:membership]
    })
  end

  defmodule MembershipsResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "MembershipsResponse",
      type: :object,
      properties: %{memberships: %Schema{type: :array, items: Membership}},
      required: [:memberships]
    })
  end

  defmodule TargetAttributes do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "TargetAttributes",
      type: :object,
      properties: %{
        security_code: %Schema{type: :string},
        market: %Schema{type: :string},
        display_name: %Schema{type: :string},
        sector: %Schema{type: :string},
        tags: %Schema{type: :array, items: %Schema{type: :string}},
        active: %Schema{type: :boolean},
        source_reference: %Schema{type: :string, maxLength: 1000, nullable: true},
        verified_at: %Schema{type: :string, format: :"date-time", nullable: true}
      }
    })
  end

  defmodule CreateTargetAttributes do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CreateTargetAttributes",
      type: :object,
      properties: %{
        security_code: %Schema{type: :string},
        market: %Schema{type: :string},
        display_name: %Schema{type: :string},
        sector: %Schema{type: :string},
        tags: %Schema{type: :array, items: %Schema{type: :string}},
        active: %Schema{type: :boolean, default: true},
        source_reference: %Schema{type: :string, maxLength: 1000, nullable: true},
        verified_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:security_code, :market, :display_name, :sector]
    })
  end

  defmodule CreateTargetRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "CreateTargetRequest",
      type: :object,
      properties: %{target: CreateTargetAttributes},
      required: [:target]
    })
  end

  defmodule UpdateTargetRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UpdateTargetRequest",
      type: :object,
      properties: %{target: TargetAttributes},
      required: [:target]
    })
  end

  defmodule Target do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Target",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        security_code: %Schema{type: :string},
        market: %Schema{type: :string},
        display_name: %Schema{type: :string},
        sector: %Schema{type: :string},
        tags: %Schema{type: :array, items: %Schema{type: :string}},
        active: %Schema{type: :boolean},
        source_reference: %Schema{type: :string, maxLength: 1000, nullable: true},
        verified_at: %Schema{type: :string, format: :"date-time", nullable: true},
        memberships: %Schema{type: :array, items: Membership}
      },
      required: [:id, :security_code, :market, :display_name, :sector, :tags, :active]
    })
  end

  defmodule TargetResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "TargetResponse",
      type: :object,
      properties: %{target: Target},
      required: [:target]
    })
  end

  defmodule TargetsResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "TargetsResponse",
      type: :object,
      properties: %{targets: %Schema{type: :array, items: Target}},
      required: [:targets]
    })
  end
end
