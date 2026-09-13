function obsoleteTaggedVersions(versions, retain) {
  return versions
    .filter((version) => version.metadata?.container?.tags?.length > 0)
    .sort((left, right) => Date.parse(right.created_at) - Date.parse(left.created_at))
    .slice(retain);
}

async function prunePackageVersions({ github, context, retain = 2 }) {
  const versions = await github.paginate(
    github.rest.packages.getAllPackageVersionsForPackageOwnedByUser,
    {
      package_type: "container",
      package_name: context.repo.repo,
      username: context.repo.owner,
      per_page: 100,
    },
  );

  for (const version of obsoleteTaggedVersions(versions, retain)) {
    await github.rest.packages.deletePackageVersionForUser({
      package_type: "container",
      package_name: context.repo.repo,
      username: context.repo.owner,
      package_version_id: version.id,
    });
  }
}

module.exports = { obsoleteTaggedVersions, prunePackageVersions };
