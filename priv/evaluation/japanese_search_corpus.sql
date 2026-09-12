\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE evaluation_documents (
  id integer PRIMARY KEY,
  title text NOT NULL,
  content text NOT NULL,
  derived_search_text text NOT NULL
);

INSERT INTO evaluation_documents (id, title, content, derived_search_text) VALUES
  (1, '第1四半期決算説明資料', '売上高は前年同期比12％増となりました。', '第1四半期決算説明資料 売上高は前年同期比12%増となりました。'),
  (2, '業績予想の修正', '通期の業績見通しを見直します。', '業績予想の修正 通期の業績見通しを見直します。'),
  (3, 'PostgreSQL 18 運用メモ', 'GIN index の再構築手順です。', 'postgresql 18 運用メモ gin index の再構築手順です。'),
  (4, '株主総会招集通知', '議決権行使の案内を掲載しました。', '株主総会招集通知 議決権行使の案内を掲載しました。'),
  (5, '統合報告書', '環境目標と人材施策を説明します。', '統合報告書 環境目標と人材施策を説明します。'),
  (6, '海外事業の進捗', '前年同期の売上高を記載します。', '海外事業の進捗 前年同期の売上高を記載します。');

CREATE INDEX evaluation_documents_search_text_trgm_index
  ON evaluation_documents USING GIN (derived_search_text gin_trgm_ops);

CREATE TABLE evaluation_cases (
  raw_query text PRIMARY KEY,
  normalized_query text,
  expected_ids integer[],
  expected_outcome text NOT NULL CHECK (expected_outcome IN ('matches', 'reject'))
);

INSERT INTO evaluation_cases (raw_query, normalized_query, expected_ids, expected_outcome) VALUES
  ('決算説明', '決算説明', ARRAY[1], 'matches'),
  ('前年同期比', '前年同期比', ARRAY[1], 'matches'),
  ('業績', '業績', ARRAY[2], 'matches'),
  ('PostgreSQL 18', 'postgresql 18', ARRAY[3], 'matches'),
  ('ＰｏｓｔｇｒｅＳＱＬ　１８', 'postgresql 18', ARRAY[3], 'matches'),
  ('株主', '株主', ARRAY[4], 'matches'),
  ('前年同期非', '前年同期非', ARRAY[]::integer[], 'matches'),
  ('株', NULL, NULL, 'reject'),
  ('！', NULL, NULL, 'reject');

DO $$
DECLARE
  evaluation_case evaluation_cases%ROWTYPE;
  actual_ids integer[];
BEGIN
  FOR evaluation_case IN SELECT * FROM evaluation_cases LOOP
    IF evaluation_case.expected_outcome = 'reject' THEN
      IF evaluation_case.normalized_query IS NOT NULL THEN
        RAISE EXCEPTION 'rejected query % must not have a normalized value', evaluation_case.raw_query;
      END IF;
    ELSE
      SELECT coalesce(array_agg(id ORDER BY id), ARRAY[]::integer[])
        INTO actual_ids
        FROM evaluation_documents
       WHERE derived_search_text ILIKE '%' || evaluation_case.normalized_query || '%';

      IF actual_ids IS DISTINCT FROM evaluation_case.expected_ids THEN
        RAISE EXCEPTION 'query % expected %, got %',
          evaluation_case.raw_query, evaluation_case.expected_ids, actual_ids;
      END IF;
    END IF;
  END LOOP;
END
$$;

INSERT INTO evaluation_documents (id, title, content, derived_search_text)
SELECT
  10_000 + sequence,
  'Synthetic disclosure ' || sequence,
  'Unrelated disclosure body ' || sequence,
  'synthetic disclosure ' || sequence || ' unrelated disclosure body ' || sequence
FROM generate_series(1, 10_000) AS sequence;

ANALYZE evaluation_documents;

SELECT count(*) AS corpus_documents FROM evaluation_documents;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF)
SELECT id
FROM evaluation_documents
WHERE derived_search_text ILIKE '%前年同期比%';
