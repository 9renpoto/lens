function tagsFor(version) {
  return version.metadata?.container?.tags ?? [];
}

/**
 * Return only obsolete tagged image versions.
 *
 * Untagged manifests are deliberately retained because a multi-platform image
 * index can reference them. Deleting one of those manifests can make a retained
 * release tag unpullable. GitHub's package API does not expose the index-child
 * relationship, so retaining untagged manifests is the safe boundary here.
 */
export function obsoleteVersionIds(versions, keepCount = 2) {
  return versions
    .filter((version) => tagsFor(version).length > 0)
    .sort((left, right) => {
      const createdAt = Date.parse(right.created_at) - Date.parse(left.created_at);
      return createdAt || String(right.id).localeCompare(String(left.id));
    })
    .slice(keepCount)
    .map((version) => version.id);
}
