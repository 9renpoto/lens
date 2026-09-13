import assert from "node:assert/strict";
import test from "node:test";

import { obsoleteVersionIds } from "./ghcr_retention.mjs";

const version = (id, created_at, tags) => ({
  id,
  created_at,
  metadata: { container: { tags } },
});

test("keeps the two newest tagged versions and their untagged manifests", () => {
  const versions = [
    version(10, "2026-01-01T00:00:00Z", ["v0.1.0", "sha-release"]),
    version(11, "2026-01-01T00:00:00Z", []),
    version(20, "2026-01-02T00:00:00Z", ["latest", "sha-main"]),
    version(21, "2026-01-02T00:00:00Z", []),
    version(30, "2025-12-01T00:00:00Z", ["sha-old"]),
    version(31, "2025-12-01T00:00:00Z", []),
  ];

  assert.deepEqual(obsoleteVersionIds(versions), [30]);
});

test("does not delete an untagged manifest when no tagged version is retained", () => {
  const versions = [version(1, "2026-01-01T00:00:00Z", [])];

  assert.deepEqual(obsoleteVersionIds(versions), []);
});
