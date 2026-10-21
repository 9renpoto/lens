const assert = require("node:assert/strict");
const test = require("node:test");
const {
  selectSemver,
  selectReleaseBump,
  incrementVersion,
} = require("./select-release-bump");

const config = {
  changelog: {
    exclude: { labels: ["ignore-for-release"], authors: ["excluded-bot"] },
    categories: [
      {
        title: ":boom: Type: Breaking Change",
        labels: ["Type: Breaking Change", "breaking-alias"],
      },
      { title: ":bug: Type: Bug", labels: ["Type: Bug", "bug"] },
      { title: ":house: Refactoring", labels: ["Type: Refactoring"] },
      {
        title: ":rocket: Type: Feature",
        labels: ["Type: Feature", "enhancement"],
      },
      { title: "Other Changes", labels: ["*"] },
    ],
  },
};
function pr(number, labels, overrides = {}) {
  return {
    number,
    labels: labels.map((name) => ({ name })),
    user: { login: "contributor" },
    merged_at: "2026-10-20T00:00:00Z",
    merge_commit_sha: `merge-${number}`,
    base: { ref: "main", repo: { full_name: "owner/repo" } },
    ...overrides,
  };
}

test("the highest increment wins across PRs and category aliases", () => {
  assert.equal(
    selectSemver([pr(1, ["bug"]), pr(2, ["enhancement"])], config),
    "minor",
  );
  assert.equal(selectSemver([pr(1, ["bug", "enhancement"])], config), "minor");
  assert.equal(
    selectSemver([pr(1, ["enhancement"]), pr(2, ["breaking-alias"])], config),
    "major",
  );
});

test("other included changes use patch; exclusions and empty input do not bump", () => {
  assert.equal(
    selectSemver([pr(1, []), pr(2, ["Type: Refactoring"])], config),
    "patch",
  );
  assert.equal(
    selectSemver(
      [pr(1, ["Type: Breaking Change", "ignore-for-release"])],
      config,
    ),
    "",
  );
  assert.equal(
    selectSemver(
      [pr(1, ["enhancement"], { user: { login: "excluded-bot" } })],
      config,
    ),
    "",
  );
  assert.equal(selectSemver([], config), "");
});

test("category-specific exclusions apply and missing semantic categories fail safely", () => {
  const custom = structuredClone(config);
  custom.changelog.categories[0].exclude = { labels: ["nonbreaking"] };
  assert.equal(
    selectSemver([pr(1, ["breaking-alias", "nonbreaking"])], custom),
    "patch",
  );
  assert.throws(
    () => selectSemver([pr(1, [])], { changelog: { categories: [] } }),
    /categories/,
  );
});

test("version increments are deterministic and reject unsupported input", () => {
  assert.equal(incrementVersion("v0.2.9", "patch"), "0.2.10");
  assert.equal(incrementVersion("v0.2.9", "minor"), "0.3.0");
  assert.equal(incrementVersion("v0.2.9", "major"), "1.0.0");
  assert.throws(() => incrementVersion("v1.0.0-rc.1", "minor"), /stable/);
  assert.throws(() => incrementVersion("v1.0.0", "invalid"), /increment/);
});

function client({
  commits = [{ sha: "merge-1" }],
  prs = [pr(1, ["enhancement"])],
  status = "ahead",
  releaseError,
} = {}) {
  const calls = [];
  const github = {
    rest: {
      repos: {
        getLatestRelease: async () => {
          if (releaseError) throw releaseError;
          return { data: { tag_name: "v0.2.0" } };
        },
        compareCommitsWithBasehead: async (request) => {
          calls.push(request);
          return {
            data: {
              status,
              total_commits: commits.length,
              commits: commits.slice(
                (request.page - 1) * 100,
                request.page * 100,
              ),
            },
          };
        },
        listPullRequestsAssociatedWithCommit: "associated-prs",
      },
    },
    paginate: async (_endpoint, { commit_sha }) =>
      prs.filter(
        (entry) =>
          entry.related?.includes(commit_sha) ||
          entry.merge_commit_sha === commit_sha,
      ),
  };
  return { github, calls };
}
const context = {
  repo: { owner: "owner", repo: "repo" },
  sha: "fixed-main-sha",
};

test("compares the stable release to the scheduled SHA and deduplicates merged PRs", async () => {
  const { github, calls } = client({
    commits: [{ sha: "feature-commit" }, { sha: "merge-1" }],
    prs: [pr(1, ["enhancement"], { related: ["feature-commit", "merge-1"] })],
  });
  assert.deepEqual(await selectReleaseBump({ github, context, config }), {
    semver: "minor",
    previousTag: "v0.2.0",
  });
  assert.equal(calls[0].basehead, "v0.2.0...fixed-main-sha");
});

test("paginates release history beyond the first 100 commits", async () => {
  const commits = Array.from({ length: 101 }, (_, index) => ({
    sha: `commit-${index}`,
  }));
  const { github, calls } = client({
    commits,
    prs: [
      pr(1, ["Type: Breaking Change"], {
        merge_commit_sha: "commit-100",
        related: commits.map(({ sha }) => sha),
      }),
    ],
  });
  assert.equal(
    (await selectReleaseBump({ github, context, config })).semver,
    "major",
  );
  assert.equal(calls.length, 2);
});

test("an identical release has nothing to bump", async () => {
  const { github } = client({ commits: [], prs: [], status: "identical" });
  assert.deepEqual(await selectReleaseBump({ github, context, config }), {
    semver: "",
    previousTag: "v0.2.0",
  });
});

test("missing or divergent history and unassociated changes fail instead of guessing", async () => {
  for (const options of [
    { releaseError: new Error("No stable release") },
    { status: "diverged" },
    { commits: [{ sha: "unassociated" }], prs: [] },
  ]) {
    const { github } = client(options);
    await assert.rejects(() => selectReleaseBump({ github, context, config }));
  }
});

test("PRs outside main and PRs merged before the release do not classify new commits", async () => {
  const { github } = client({
    prs: [
      pr(1, ["enhancement"], {
        base: { ref: "other", repo: { full_name: "owner/repo" } },
      }),
      pr(2, ["Type: Breaking Change"], { related: ["merge-1"] }),
    ],
  });
  await assert.rejects(
    () => selectReleaseBump({ github, context, config }),
    /associated/,
  );
});
