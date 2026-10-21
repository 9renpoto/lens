// @ts-check

/**
 * @typedef {"major" | "minor" | "patch"} SemverIncrement
 * @typedef {SemverIncrement | ""} SemverSelection Empty means no included changes.
 * @typedef {{labels?: string[], authors?: string[]}} ReleaseExclusions
 * @typedef {{title: string, labels: string[], exclude?: ReleaseExclusions}} ReleaseCategory
 * @typedef {{changelog: {categories: ReleaseCategory[], exclude?: ReleaseExclusions}}} ReleaseConfig
 * @typedef {{labels: {name: string}[], user: {login: string}}} ReleaseCandidate
 * @typedef {ReleaseCandidate & {
 *   number: number,
 *   merged_at: string | null,
 *   merge_commit_sha: string | null,
 *   base: {ref: string, repo: {full_name: string}}
 * }} ReleasePullRequest
 * @typedef {{owner: string, repo: string}} Repository
 * @typedef {{sha: string}} ReleaseCommit
 * @typedef {Repository & {basehead: string, per_page: number, page: number}} ComparisonRequest
 * @typedef {Repository & {commit_sha: string, per_page: number}} AssociatedPullsRequest
 * @typedef {(parameters: AssociatedPullsRequest) => Promise<{data: ReleasePullRequest[]}>} ListAssociatedPulls
 * @typedef {{semver: SemverSelection, previousTag: string}} ReleaseBump
 */

/**
 * The subset of the github-script client used by the release selector.
 * @typedef {object} ReleaseGitHubClient
 * @property {{repos: {
 *   getLatestRelease: (parameters: Repository) => Promise<{data: {tag_name: string}}>,
 *   compareCommitsWithBasehead: (parameters: ComparisonRequest) => Promise<{
 *     data: {status: string, total_commits: number, commits: ReleaseCommit[]}
 *   }>,
 *   listPullRequestsAssociatedWithCommit: ListAssociatedPulls
 * }}} rest
 * @property {(method: ListAssociatedPulls, parameters: AssociatedPullsRequest) => Promise<ReleasePullRequest[]>} paginate
 */

/** @type {readonly SemverSelection[]} */
const increments = ["", "patch", "minor", "major"];
/** @type {Readonly<Record<string, SemverIncrement>>} */
const semanticCategories = {
  ":boom: Type: Breaking Change": "major",
  ":rocket: Type: Feature": "minor",
};

/**
 * @param {ReleaseCandidate} pull
 * @param {ReleaseExclusions} [exclusions]
 * @returns {boolean}
 */
function excluded(pull, exclusions = {}) {
  return (
    (exclusions.authors ?? []).includes(pull.user.login) ||
    (exclusions.labels ?? []).some(
      (label) =>
        label === "*" || pull.labels.some(({ name }) => name === label),
    )
  );
}

/**
 * @param {ReleaseCandidate[]} pulls
 * @param {ReleaseConfig} config
 * @returns {SemverSelection}
 */
function selectSemver(pulls, config) {
  const categories = config.changelog?.categories ?? [];
  for (const title of Object.keys(semanticCategories)) {
    if (!categories.some((category) => category.title === title)) {
      throw new Error(`Missing release categories: ${title}`);
    }
  }
  let rank = 0;
  for (const pull of pulls) {
    if (excluded(pull, config.changelog.exclude)) continue;
    for (const category of categories) {
      if (excluded(pull, category.exclude)) continue;
      if (
        category.labels.some(
          (label) =>
            label === "*" || pull.labels.some(({ name }) => name === label),
        )
      ) {
        rank = Math.max(
          rank,
          increments.indexOf(semanticCategories[category.title] ?? "patch"),
        );
      }
    }
  }
  return increments[rank];
}

/**
 * @param {string} tag A stable tag in vMAJOR.MINOR.PATCH format.
 * @param {SemverIncrement} semver
 * @returns {string} The next version without the v prefix.
 */
function incrementVersion(tag, semver) {
  const match = /^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.exec(tag);
  if (!match) throw new Error(`Expected a stable version tag: ${tag}`);
  const index = ["major", "minor", "patch"].indexOf(semver);
  if (index < 0) throw new Error(`Unsupported version increment: ${semver}`);
  const version = match.slice(1).map(BigInt);
  version[index] += 1n;
  version.fill(0n, index + 1);
  return version.join(".");
}

/**
 * @param {{
 *   github: ReleaseGitHubClient,
 *   context: {repo: Repository, sha: string},
 *   config: ReleaseConfig
 * }} options
 * @returns {Promise<ReleaseBump>}
 */
async function selectReleaseBump({ github, context, config }) {
  const { data: release } = await github.rest.repos.getLatestRelease(
    context.repo,
  );
  const previousTag = release.tag_name;
  incrementVersion(previousTag, "patch");
  /** @type {ReleaseCommit[]} */
  const commits = [];
  for (let page = 1; ; page += 1) {
    const { data } = await github.rest.repos.compareCommitsWithBasehead({
      ...context.repo,
      basehead: `${previousTag}...${context.sha}`,
      per_page: 100,
      page,
    });
    if (data.status === "identical") return { semver: "", previousTag };
    if (data.status !== "ahead")
      throw new Error(
        "Stable release is not an ancestor of the scheduled commit",
      );
    if (!data.commits.length) throw new Error("Incomplete release comparison");
    commits.push(...data.commits);
    if (commits.length >= data.total_commits) break;
  }
  /** @type {ReadonlySet<string | null>} */
  const shas = new Set(commits.map(({ sha }) => sha));
  /** @type {Map<number, ReleasePullRequest>} */
  const pulls = new Map();
  for (const { sha } of commits) {
    const associated = await github.paginate(
      github.rest.repos.listPullRequestsAssociatedWithCommit,
      {
        ...context.repo,
        commit_sha: sha,
        per_page: 100,
      },
    );
    const included = associated.filter(
      (pull) =>
        pull.merged_at &&
        pull.base.ref === "main" &&
        pull.base.repo.full_name ===
          `${context.repo.owner}/${context.repo.repo}` &&
        shas.has(pull.merge_commit_sha),
    );
    if (!included.length)
      throw new Error(`No merged main PR associated with commit ${sha}`);
    for (const pull of included) pulls.set(pull.number, pull);
  }
  return { semver: selectSemver([...pulls.values()], config), previousTag };
}

module.exports = { selectSemver, selectReleaseBump, incrementVersion };
