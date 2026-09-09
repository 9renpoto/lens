const assert = require("node:assert/strict");
const test = require("node:test");

const { obsoleteTaggedVersions } = require("./prune-package-versions");

test("keeps untagged manifests referenced by OCI indexes", () => {
  const versions = [
    version(1, "2026-09-09T03:00:00Z", ["latest", "sha-current"]),
    version(2, "2026-09-09T02:59:00Z", []),
    version(3, "2026-09-09T02:58:00Z", []),
    version(4, "2026-09-08T03:00:00Z", ["sha-previous"]),
    version(5, "2026-09-08T02:59:00Z", []),
    version(6, "2026-09-07T03:00:00Z", ["sha-obsolete"]),
  ];

  assert.deepEqual(
    obsoleteTaggedVersions(versions, 2).map(({ id }) => id),
    [6],
  );
});

function version(id, created_at, tags) {
  return { id, created_at, metadata: { container: { tags } } };
}
