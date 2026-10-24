-- Current application schema. Initialize only an empty database.

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;

CREATE FUNCTION public.earnings_search_vector(input text) RETURNS tsvector
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
BEGIN
  RETURN to_tsvector('simple', input);
EXCEPTION WHEN program_limit_exceeded THEN
  RETURN NULL;
END;
$$;

CREATE FUNCTION public.protect_earnings_acquisition() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.release_id IS NULL
     AND NEW.release_id IS NOT NULL
     AND OLD.status = 'success'
     AND ROW(NEW.id, NEW.acquisition_id, NEW.issuer_code, NEW.url,
             NEW.acquired_at, NEW.status, NEW.failure_reason,
             NEW.original_id, NEW.inserted_at)
         IS NOT DISTINCT FROM
         ROW(OLD.id, OLD.acquisition_id, OLD.issuer_code, OLD.url,
             OLD.acquired_at, OLD.status, OLD.failure_reason,
             OLD.original_id, OLD.inserted_at)
     AND EXISTS (SELECT 1 FROM earnings_releases r
                 WHERE r.id = NEW.release_id AND r.issuer_code = NEW.issuer_code)
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'earnings acquisition provenance is immutable';
END;
$$;

CREATE FUNCTION public.protect_earnings_assessment() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'earnings assessment history is immutable';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM earnings_http_checks h
    JOIN earnings_acquisitions a ON a.id = h.acquisition_id
    JOIN earnings_sources s ON s.id = NEW.source_id
    WHERE h.id = NEW.http_check_id AND h.kind = 'pdf' AND h.status = 'success'
      AND a.status = 'success' AND a.original_id IS NOT NULL
      AND a.issuer_code = h.issuer_code AND s.target_id = NEW.target_id
      AND h.metadata->>'source_id' = s.id::text
      AND h.metadata->>'target_id' = s.target_id::text
  ) THEN
    RAISE EXCEPTION 'assessment requires a successful registered-source candidate';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.protect_earnings_http_check() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'earnings HTTP check facts are immutable';
  END IF;
  IF NEW.acquisition_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM earnings_acquisitions a
    WHERE a.id = NEW.acquisition_id AND a.issuer_code = NEW.issuer_code
      AND a.status = NEW.status AND a.acquired_at = NEW.checked_at
      AND a.acquisition_id = 'http:' || NEW.check_id
      AND a.failure_reason IS NOT DISTINCT FROM NEW.failure_reason
      AND (NEW.status <> 'success' OR EXISTS (
        SELECT 1 FROM earnings_originals o WHERE o.id = a.original_id
          AND o.sha256 = NEW.sha256 AND o.byte_size = NEW.byte_size
      ))
      AND a.url = CASE WHEN NEW.status = 'success' THEN NEW.final_url ELSE NEW.url END
  ) THEN
    RAISE EXCEPTION 'HTTP check acquisition facts do not match'
      USING ERRCODE = '23514', CONSTRAINT = 'earnings_http_check_acquisition_facts';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.reject_earnings_original_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'earnings originals are immutable';
END;
$$;

CREATE FUNCTION public.reject_earnings_release_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'earnings release identity is immutable';
END;
$$;

CREATE TABLE public.analysis_memberships (
    id uuid NOT NULL,
    target_id uuid NOT NULL,
    index_name character varying(255) DEFAULT 'nikkei_225'::character varying NOT NULL,
    effective_from date NOT NULL,
    effective_to date,
    source_reference text,
    verified_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT effective_to_must_be_on_or_after_effective_from CHECK (((effective_to IS NULL) OR (effective_to >= effective_from)))
);

CREATE TABLE public.analysis_targets (
    id uuid NOT NULL,
    security_code character varying(255) NOT NULL,
    market character varying(255) NOT NULL,
    display_name character varying(255) NOT NULL,
    sector character varying(255) NOT NULL,
    tags character varying(255)[] DEFAULT ARRAY[]::character varying[] NOT NULL,
    active boolean DEFAULT true NOT NULL,
    source_reference text,
    verified_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);

CREATE TABLE public.documents (
    id uuid NOT NULL,
    identity_key text NOT NULL,
    canonical_url text,
    title text,
    content text NOT NULL,
    author text,
    published_at timestamp without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    content_hash character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS ((setweight(to_tsvector('simple'::regconfig, COALESCE(title, ''::text)), 'A'::"char") || setweight(to_tsvector('simple'::regconfig, content), 'B'::"char"))) STORED,
    search_text text DEFAULT ''::text NOT NULL,
    search_title text DEFAULT ''::text NOT NULL
);

CREATE TABLE public.earnings_acquisitions (
    id uuid NOT NULL,
    acquisition_id character varying(255) NOT NULL,
    issuer_code character varying(255) NOT NULL,
    url text NOT NULL,
    acquired_at timestamp without time zone NOT NULL,
    status character varying(255) NOT NULL,
    failure_reason text,
    original_id uuid,
    release_id uuid,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT earnings_acquisitions_status_check CHECK (((((status)::text = 'success'::text) AND (original_id IS NOT NULL) AND (failure_reason IS NULL)) OR (((status)::text = 'failed'::text) AND (original_id IS NULL) AND (release_id IS NULL) AND (failure_reason IS NOT NULL))))
);

CREATE TABLE public.earnings_assessments (
    id uuid NOT NULL,
    http_check_id uuid NOT NULL,
    target_id uuid NOT NULL,
    source_id uuid NOT NULL,
    outcome text NOT NULL,
    document_kind text,
    assessor text NOT NULL,
    assessor_version text NOT NULL,
    reason text NOT NULL,
    identity jsonb DEFAULT '{}'::jsonb NOT NULL,
    evidence jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT earnings_assessment_json CHECK (((jsonb_typeof(identity) = 'object'::text) AND (jsonb_typeof(evidence) = 'object'::text) AND (evidence <> '{}'::jsonb) AND (octet_length((identity)::text) <= 65536) AND (octet_length((evidence)::text) <= 65536))),
    CONSTRAINT earnings_assessment_kind CHECK ((((document_kind IS NULL) OR (document_kind = ANY (ARRAY['earnings_release'::text, 'correction'::text, 'earnings_presentation'::text]))) AND ((outcome <> 'accepted'::text) OR (document_kind IS NOT NULL)))),
    CONSTRAINT earnings_assessment_outcome CHECK ((outcome = ANY (ARRAY['accepted'::text, 'excluded'::text, 'pending'::text]))),
    CONSTRAINT earnings_assessment_text CHECK ((((char_length(btrim(assessor)) >= 1) AND (char_length(btrim(assessor)) <= 100)) AND ((char_length(btrim(assessor_version)) >= 1) AND (char_length(btrim(assessor_version)) <= 100)) AND ((char_length(btrim(reason)) >= 1) AND (char_length(btrim(reason)) <= 1000))))
);

CREATE TABLE public.earnings_extractions (
    id bigint NOT NULL,
    original_id uuid NOT NULL,
    extractor text NOT NULL,
    extractor_version text NOT NULL,
    status text NOT NULL,
    extraction_options jsonb DEFAULT '{}'::jsonb NOT NULL,
    text text,
    failure_reason text,
    finished_at timestamp without time zone,
    inserted_at timestamp without time zone NOT NULL,
    search_text text DEFAULT ''::text NOT NULL,
    search_vector tsvector GENERATED ALWAYS AS (public.earnings_search_vector(text)) STORED,
    CONSTRAINT extraction_options_object CHECK ((jsonb_typeof(extraction_options) = 'object'::text)),
    CONSTRAINT extraction_outcome CHECK ((((status = 'pending'::text) AND (text IS NULL) AND (failure_reason IS NULL) AND (finished_at IS NULL)) OR ((status = 'succeeded'::text) AND (text IS NOT NULL) AND (length(btrim(text)) > 0) AND (failure_reason IS NULL) AND (finished_at IS NOT NULL)) OR ((status = 'failed'::text) AND (text IS NULL) AND (failure_reason IS NOT NULL) AND (length(btrim(failure_reason)) > 0) AND (finished_at IS NOT NULL))))
);

CREATE SEQUENCE public.earnings_extractions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.earnings_extractions_id_seq OWNED BY public.earnings_extractions.id;

CREATE TABLE public.earnings_http_checks (
    id uuid NOT NULL,
    check_id character varying(180) NOT NULL,
    issuer_code character varying(255) NOT NULL,
    kind character varying(255) NOT NULL,
    url text NOT NULL,
    final_url text NOT NULL,
    checked_at timestamp without time zone NOT NULL,
    published_on date,
    status character varying(255) NOT NULL,
    failure_reason character varying(255),
    http_status integer,
    requests integer NOT NULL,
    retryable boolean NOT NULL,
    response_headers jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    sha256 character varying(255),
    byte_size bigint,
    acquisition_id uuid,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT earnings_http_check_acquisition CHECK (((((kind)::text = 'pdf'::text) AND (((status)::text = 'success'::text) OR (((status)::text = 'failed'::text) AND (requests > 0))) AND (acquisition_id IS NOT NULL)) OR ((((kind)::text = 'listing'::text) OR ((status)::text = 'not_modified'::text) OR (requests = 0)) AND (acquisition_id IS NULL)))),
    CONSTRAINT earnings_http_check_bounds CHECK ((((char_length((issuer_code)::text) >= 1) AND (char_length((issuer_code)::text) <= 50)) AND (btrim((issuer_code)::text) <> ''::text) AND ((kind)::text = ANY ((ARRAY['pdf'::character varying, 'listing'::character varying])::text[])) AND ((requests >= 0) AND (requests <= 4)) AND ((http_status IS NULL) OR ((http_status >= 100) AND (http_status <= 599))) AND ((byte_size IS NULL) OR ((byte_size >= 0) AND (byte_size <=
CASE
    WHEN ((kind)::text = 'pdf'::text) THEN 20971520
    ELSE 2097152
END))))),
    CONSTRAINT earnings_http_check_outcome CHECK (((((status)::text = 'success'::text) AND (failure_reason IS NULL) AND (http_status IS NOT NULL) AND (http_status = 200) AND (requests > 0) AND (sha256 IS NOT NULL) AND ((sha256)::text ~ '^[0-9a-f]{64}$'::text) AND (byte_size IS NOT NULL)) OR (((status)::text = 'not_modified'::text) AND (failure_reason IS NULL) AND (http_status IS NOT NULL) AND (http_status = 304) AND (requests > 0) AND (sha256 IS NULL) AND (byte_size IS NULL)) OR (((status)::text = 'failed'::text) AND (failure_reason IS NOT NULL) AND (sha256 IS NULL) AND (byte_size IS NULL)))),
    CONSTRAINT earnings_http_check_response CHECK ((((requests > 0) OR ((final_url = url) AND (http_status IS NULL) AND (response_headers = '{}'::jsonb))) AND (((status)::text = 'failed'::text) OR (retryable = false))))
);

CREATE TABLE public.earnings_originals (
    id uuid NOT NULL,
    sha256 character varying(255) NOT NULL,
    byte_size integer NOT NULL,
    key text NOT NULL,
    endpoint text NOT NULL,
    bucket text NOT NULL,
    verified_at timestamp without time zone NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    CONSTRAINT earnings_originals_size_check CHECK (byte_size > 0 AND byte_size <= 20971520),
    CONSTRAINT earnings_originals_reference_check CHECK (sha256 ~ '^[0-9a-f]{64}$' AND key = 'earnings/originals/sha256/' || sha256 || '.pdf' AND endpoint <> '' AND bucket <> '')
);

CREATE TABLE public.earnings_releases (
    id uuid NOT NULL,
    issuer_code character varying(255) NOT NULL,
    fiscal_year_end date NOT NULL,
    period character varying(255) NOT NULL,
    category character varying(255) NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT earnings_releases_period_check CHECK (((period)::text = ANY ((ARRAY['q1'::character varying, 'q2'::character varying, 'q3'::character varying, 'full_year'::character varying])::text[])))
);

CREATE TABLE public.earnings_sources (
    id uuid NOT NULL,
    target_id uuid NOT NULL,
    listing_url text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    CONSTRAINT earnings_source_url_length CHECK (((octet_length(listing_url) >= 1) AND (octet_length(listing_url) <= 2048)))
);

CREATE TABLE public.observations (
    id uuid NOT NULL,
    source_id uuid NOT NULL,
    document_id uuid NOT NULL,
    observed_at timestamp without time zone NOT NULL,
    content_hash character varying(255) NOT NULL,
    fetch_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    entry_url text,
    primary_source_url text,
    feed_format character varying(255) DEFAULT 'unknown'::character varying NOT NULL,
    acquisition_kind character varying(255) DEFAULT 'unknown'::character varying NOT NULL,
    publisher_authority character varying(255) DEFAULT 'unknown'::character varying NOT NULL,
    acquisition_metadata_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    reported_published_at timestamp without time zone,
    CONSTRAINT observations_acquisition_kind_valid CHECK (((acquisition_kind)::text = ANY ((ARRAY['direct'::character varying, 'conversion_service'::character varying, 'rsshub'::character varying, 'unknown'::character varying])::text[]))),
    CONSTRAINT observations_feed_format_valid CHECK (((feed_format)::text = ANY ((ARRAY['rss_2_0'::character varying, 'atom'::character varying, 'rss_1_0'::character varying, 'unknown'::character varying])::text[]))),
    CONSTRAINT observations_publisher_authority_valid CHECK (((publisher_authority)::text = ANY ((ARRAY['official'::character varying, 'third_party'::character varying, 'unknown'::character varying])::text[])))
);

CREATE TABLE public.source_runs (
    source_id uuid NOT NULL,
    locked_at timestamp without time zone NOT NULL
);

CREATE TABLE public.sources (
    id uuid NOT NULL,
    endpoint_url text NOT NULL,
    title character varying(255),
    enabled boolean DEFAULT true NOT NULL,
    poll_interval_seconds integer NOT NULL,
    next_fetch_at timestamp without time zone,
    etag character varying(255),
    last_modified character varying(255),
    last_attempt_at timestamp without time zone,
    last_success_at timestamp without time zone,
    last_error text,
    failure_count integer DEFAULT 0 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    inserted_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    feed_format character varying(255) DEFAULT 'unknown'::character varying NOT NULL,
    acquisition_kind character varying(255) DEFAULT 'unknown'::character varying NOT NULL,
    publisher_authority character varying(255) DEFAULT 'unknown'::character varying NOT NULL,
    original_feed_url text,
    acquisition_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT failure_count_must_not_be_negative CHECK ((failure_count >= 0)),
    CONSTRAINT poll_interval_seconds_must_be_positive CHECK ((poll_interval_seconds > 0)),
    CONSTRAINT sources_acquisition_kind_valid CHECK (((acquisition_kind)::text = ANY ((ARRAY['direct'::character varying, 'conversion_service'::character varying, 'rsshub'::character varying, 'unknown'::character varying])::text[]))),
    CONSTRAINT sources_feed_format_valid CHECK (((feed_format)::text = ANY ((ARRAY['rss_2_0'::character varying, 'atom'::character varying, 'rss_1_0'::character varying, 'unknown'::character varying])::text[]))),
    CONSTRAINT sources_publisher_authority_valid CHECK (((publisher_authority)::text = ANY ((ARRAY['official'::character varying, 'third_party'::character varying, 'unknown'::character varying])::text[])))
);

ALTER TABLE ONLY public.earnings_extractions ALTER COLUMN id SET DEFAULT nextval('public.earnings_extractions_id_seq'::regclass);

ALTER TABLE ONLY public.analysis_memberships
    ADD CONSTRAINT analysis_memberships_no_overlapping_intervals EXCLUDE USING gist (target_id WITH =, index_name WITH =, daterange(effective_from, effective_to, '[]'::text) WITH &&);

ALTER TABLE ONLY public.analysis_memberships
    ADD CONSTRAINT analysis_memberships_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.analysis_targets
    ADD CONSTRAINT analysis_targets_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.earnings_acquisitions
    ADD CONSTRAINT earnings_acquisitions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.earnings_assessments
    ADD CONSTRAINT earnings_assessments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.earnings_extractions
    ADD CONSTRAINT earnings_extractions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.earnings_http_checks
    ADD CONSTRAINT earnings_http_checks_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.earnings_originals
    ADD CONSTRAINT earnings_originals_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.earnings_releases
    ADD CONSTRAINT earnings_releases_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.earnings_sources
    ADD CONSTRAINT earnings_sources_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.observations
    ADD CONSTRAINT observations_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.source_runs
    ADD CONSTRAINT source_runs_pkey PRIMARY KEY (source_id);

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT sources_pkey PRIMARY KEY (id);

CREATE INDEX analysis_memberships_index_name_effective_from_effective_to_ind ON public.analysis_memberships USING btree (index_name, effective_from, effective_to);

CREATE INDEX analysis_memberships_target_id_index ON public.analysis_memberships USING btree (target_id);

CREATE UNIQUE INDEX analysis_targets_security_code_index ON public.analysis_targets USING btree (security_code);

CREATE UNIQUE INDEX documents_canonical_url_index ON public.documents USING btree (canonical_url) WHERE (canonical_url IS NOT NULL);

CREATE UNIQUE INDEX documents_identity_key_index ON public.documents USING btree (identity_key);

CREATE INDEX documents_search_text_trgm_index ON public.documents USING gin (search_text public.gin_trgm_ops);

CREATE INDEX documents_search_vector_index ON public.documents USING gin (search_vector);

CREATE UNIQUE INDEX earnings_acquisitions_acquisition_id_index ON public.earnings_acquisitions USING btree (acquisition_id);

CREATE INDEX earnings_acquisitions_issuer_code_acquired_at_index ON public.earnings_acquisitions USING btree (issuer_code, acquired_at);

CREATE INDEX earnings_acquisitions_release_id_acquired_at_index ON public.earnings_acquisitions USING btree (release_id, acquired_at);

CREATE INDEX earnings_assessments_http_check_id_inserted_at_id_index ON public.earnings_assessments USING btree (http_check_id, inserted_at, id);

CREATE INDEX earnings_assessments_source_id_index ON public.earnings_assessments USING btree (source_id);

CREATE INDEX earnings_assessments_target_id_index ON public.earnings_assessments USING btree (target_id);

CREATE INDEX earnings_extractions_original_id_id_index ON public.earnings_extractions USING btree (original_id, id);

CREATE INDEX earnings_extractions_search_text_index ON public.earnings_extractions USING gin (search_text public.gin_trgm_ops);

CREATE INDEX earnings_extractions_search_vector_index ON public.earnings_extractions USING gin (search_vector);

CREATE UNIQUE INDEX earnings_http_checks_acquisition_id_index ON public.earnings_http_checks USING btree (acquisition_id);

CREATE UNIQUE INDEX earnings_http_checks_check_id_index ON public.earnings_http_checks USING btree (check_id);

CREATE INDEX earnings_http_checks_issuer_code_checked_at_id_index ON public.earnings_http_checks USING btree (issuer_code, checked_at, id);

CREATE UNIQUE INDEX earnings_originals_sha256_index ON public.earnings_originals USING btree (sha256);

CREATE UNIQUE INDEX earnings_releases_issuer_code_fiscal_year_end_period_category_i ON public.earnings_releases USING btree (issuer_code, fiscal_year_end, period, category);

CREATE UNIQUE INDEX earnings_sources_target_id_listing_url_index ON public.earnings_sources USING btree (target_id, listing_url);

CREATE INDEX observations_document_id_observed_at_index ON public.observations USING btree (document_id, observed_at);

CREATE UNIQUE INDEX observations_source_id_document_id_observed_at_index ON public.observations USING btree (source_id, document_id, observed_at);

CREATE INDEX observations_source_id_observed_at_index ON public.observations USING btree (source_id, observed_at);

CREATE UNIQUE INDEX sources_endpoint_url_index ON public.sources USING btree (endpoint_url);

CREATE TRIGGER earnings_acquisitions_immutable BEFORE DELETE OR UPDATE ON public.earnings_acquisitions FOR EACH ROW EXECUTE FUNCTION public.protect_earnings_acquisition();

CREATE TRIGGER earnings_assessments_protected BEFORE INSERT OR DELETE OR UPDATE ON public.earnings_assessments FOR EACH ROW EXECUTE FUNCTION public.protect_earnings_assessment();

CREATE TRIGGER earnings_http_checks_protected BEFORE INSERT OR DELETE OR UPDATE ON public.earnings_http_checks FOR EACH ROW EXECUTE FUNCTION public.protect_earnings_http_check();

CREATE TRIGGER earnings_originals_immutable BEFORE DELETE OR UPDATE ON public.earnings_originals FOR EACH ROW EXECUTE FUNCTION public.reject_earnings_original_mutation();

CREATE TRIGGER earnings_releases_immutable BEFORE DELETE OR UPDATE ON public.earnings_releases FOR EACH ROW EXECUTE FUNCTION public.reject_earnings_release_mutation();

ALTER TABLE ONLY public.analysis_memberships
    ADD CONSTRAINT analysis_memberships_target_id_fkey FOREIGN KEY (target_id) REFERENCES public.analysis_targets(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.earnings_acquisitions
    ADD CONSTRAINT earnings_acquisitions_original_id_fkey FOREIGN KEY (original_id) REFERENCES public.earnings_originals(id);

ALTER TABLE ONLY public.earnings_acquisitions
    ADD CONSTRAINT earnings_acquisitions_release_id_fkey FOREIGN KEY (release_id) REFERENCES public.earnings_releases(id);

ALTER TABLE ONLY public.earnings_assessments
    ADD CONSTRAINT earnings_assessments_http_check_id_fkey FOREIGN KEY (http_check_id) REFERENCES public.earnings_http_checks(id);

ALTER TABLE ONLY public.earnings_assessments
    ADD CONSTRAINT earnings_assessments_source_id_fkey FOREIGN KEY (source_id) REFERENCES public.earnings_sources(id);

ALTER TABLE ONLY public.earnings_assessments
    ADD CONSTRAINT earnings_assessments_target_id_fkey FOREIGN KEY (target_id) REFERENCES public.analysis_targets(id);

ALTER TABLE ONLY public.earnings_extractions
    ADD CONSTRAINT earnings_extractions_original_id_fkey FOREIGN KEY (original_id) REFERENCES public.earnings_originals(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.earnings_http_checks
    ADD CONSTRAINT earnings_http_checks_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES public.earnings_acquisitions(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.earnings_sources
    ADD CONSTRAINT earnings_sources_target_id_fkey FOREIGN KEY (target_id) REFERENCES public.analysis_targets(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.observations
    ADD CONSTRAINT observations_document_id_fkey FOREIGN KEY (document_id) REFERENCES public.documents(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.observations
    ADD CONSTRAINT observations_source_id_fkey FOREIGN KEY (source_id) REFERENCES public.sources(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.source_runs
    ADD CONSTRAINT source_runs_source_id_fkey FOREIGN KEY (source_id) REFERENCES public.sources(id) ON DELETE CASCADE;
