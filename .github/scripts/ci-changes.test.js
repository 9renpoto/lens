const assert = require("node:assert/strict");
const test = require("node:test");
const { classifyChanges, detectChanges } = require("./ci-changes");

const none = { test: false, image: false, actions: false };
const all = { test: true, image: true, actions: true };

test("documentation changes skip expensive jobs, but API docs are built and checked", () => {
  assert.deepEqual(classifyChanges(["README.md", "docs/adr/0011.md"]), none);
  assert.deepEqual(classifyChanges(["docs/api/index.html"]), {
    ...none,
    test: true,
  });
});

test("runtime inputs require tests and a fresh image", () => {
  for (const path of [
    "lib/lens.ex",
    "config/runtime.exs",
    "priv/empty",
    "rel/env.sh.eex",
    "mix.lock",
    "mix.exs",
    "Dockerfile",
    ".dockerignore",
  ]) {
    assert.deepEqual(
      classifyChanges([path]),
      { ...none, test: true, image: true },
      path,
    );
  }
});

test("test-only changes run tests without republishing the image", () => {
  for (const path of [
    "test/fixture.pdf",
    "scripts/check.exs",
    "test/pdf_native_runner_check.sh",
    ".formatter.exs",
    "mise.toml",
    ".octocov.yml",
  ]) {
    assert.deepEqual(classifyChanges([path]), { ...none, test: true }, path);
  }
});

test("workflow lint runs only for workflow and lint configuration changes", () => {
  for (const path of [
    ".github/workflows/bump.yml",
    ".github/actions/custom/action.yml",
    ".github/zizmor.yml",
    ".github/actionlint.yaml",
    ".github/actionlint-matcher.json",
  ]) {
    assert.deepEqual(classifyChanges([path]), { ...none, actions: true }, path);
  }
  assert.deepEqual(classifyChanges([".github/workflows/ci.yml"]), all);
  assert.deepEqual(
    classifyChanges([".github/scripts/prune-package-versions.js"]),
    { ...none, test: true, image: true },
  );
  assert.deepEqual(classifyChanges([".github/scripts/ci-changes.js"]), {
    ...none,
    test: true,
    image: true,
  });
});

function client(files, error) {
  const github = {
    rest: {
      pulls: { listFiles: "pull-files" },
      repos: {
        compareCommitsWithBasehead: async () => {
          if (error) throw error;
          return { data: { files, total_commits: 1 } };
        },
      },
    },
    paginate: async () => {
      if (error) throw error;
      return files;
    },
  };
  return github;
}
const context = {
  eventName: "pull_request",
  repo: { owner: "owner", repo: "repo" },
  payload: { pull_request: { number: 42 } },
};

test("PR detection includes old paths of renamed runtime files", async () => {
  const github = client([
    {
      filename: "docs/old.ex.txt",
      previous_filename: "lib/old.ex",
      status: "renamed",
    },
  ]);
  assert.deepEqual(await detectChanges({ github, context }), {
    ...none,
    test: true,
    image: true,
  });
});

test("deleted files are classified by their previous location", async () => {
  assert.deepEqual(
    await detectChanges({
      github: client([{ filename: "config/old.exs", status: "removed" }]),
      context,
    }),
    { ...none, test: true, image: true },
  );
});

test("incomplete API results and API errors conservatively run all jobs", async () => {
  const limited = Array.from({ length: 3000 }, () => ({
    filename: "README.md",
  }));
  assert.deepEqual(
    await detectChanges({ github: client(limited), context }),
    all,
  );
  assert.deepEqual(
    await detectChanges({
      github: client([], new Error("rate limited")),
      context,
    }),
    all,
  );
  const push = {
    ...context,
    eventName: "push",
    payload: { before: "a".repeat(40), after: "b".repeat(40) },
    ref: "refs/heads/main",
  };
  assert.deepEqual(
    await detectChanges({
      github: client(limited.slice(0, 300)),
      context: push,
    }),
    all,
  );
});

test("main pushes use the push comparison; tags and new history run all checks", async () => {
  const push = {
    ...context,
    eventName: "push",
    payload: { before: "a".repeat(40), after: "b".repeat(40) },
    ref: "refs/heads/main",
  };
  assert.deepEqual(
    await detectChanges({
      github: client([{ filename: "README.md" }]),
      context: push,
    }),
    none,
  );
  assert.deepEqual(
    await detectChanges({
      github: client([]),
      context: { ...push, ref: "refs/tags/v1.0.0" },
    }),
    all,
  );
  assert.deepEqual(
    await detectChanges({
      github: client([]),
      context: { ...push, payload: { before: "0".repeat(40) } },
    }),
    all,
  );
});

test("automation test changes do not republish production images", () => {
  for (const path of [
    ".github/scripts/ci-changes.test.js",
    ".github/scripts/prune-package-versions.test.js",
  ]) {
    assert.deepEqual(classifyChanges([path]), none, path);
  }
});

test("Elixir test workflow changes run application tests and lint without republishing images", () => {
  assert.deepEqual(classifyChanges([".github/workflows/test-elixir.yml"]), {
    test: true,
    image: false,
    actions: true,
  });
});
