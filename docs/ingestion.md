# Feed ingestion

Use the following command to ingest one configured source without running a scheduler:

```sh
mix lens.ingest SOURCE_ID
```

The command returns one of three outcomes: `:success`, `:not_modified`, or `:failure`.

Each request sends the source's stored ETag and Last-Modified values when available. Validators are updated only after a successful response or a `304 Not Modified` response. A malformed feed, response-size limit, HTTP error, or transport error records the failed attempt while preserving existing documents and validators.

The scheduler keeps one database-backed run claim per source. Claims older than
five minutes are reclaimed after a process crash or restart. Failed sources use
capped exponential backoff with jitter; an HTTP `Retry-After` delay is honored
up to one hour. A successful response or `304 Not Modified` resets the failure
state and returns the source to its configured polling interval.

The fetcher uses bounded request and receive timeouts, follows at most three redirects, accepts at most 5 MB per response, and rejects feeds with more than 1,000 entries. Limit failures do not claim a complete ingestion.

RSS 2.0, Atom, RDF/RSS 1.0, and RSSHub output all use the same HTTP feed path. RSSHub is only an endpoint URL stored on a source; no RSSHub route or deployment detail is part of the domain model.

## RDF/RSS 1.0 support

Lens recognizes an RDF root only when it declares the RSS 1.0 namespace and
contains an RSS channel. RSS 1.0 items may be siblings of the channel, and
namespace prefixes are not significant.

For each item, Lens supports `rdf:about`, title, link, description or encoded
content, author or Dublin Core creator, and Dublin Core date or `pubDate`.
Relative identifiers and links use applicable XML Base values. Missing or
invalid publication dates remain unknown. Lens does not implement a generic
RDF graph store.

The ingestion service is idempotent for document identity. Every successfully handled entry creates an observation, including entries whose normalized content has not changed. Entries that cannot produce canonical content are reported separately while other valid entries are retained.

The document content hash is calculated from the normalized title and body values, so formatting-only HTML differences do not create a different hash.
