const all = { test: true, image: true, actions: true };

function classifyChanges(paths) {
  const image = paths.some(
    (path) =>
      /^(lib|config|priv|rel)\//.test(path) ||
      [
        "mix.exs",
        "mix.lock",
        "Dockerfile",
        ".dockerignore",
        ".github/workflows/ci.yml",
      ].includes(path) ||
      /^\.github\/scripts\/(ci-changes|prune-package-versions)\.js$/.test(path),
  );
  return {
    test:
      image ||
      paths.some(
        (path) =>
          /\.(exs?|c|h)$/.test(path) ||
          /^(test|docs\/api)\//.test(path) ||
          [
            ".formatter.exs",
            "mise.toml",
            ".octocov.yml",
            ".github/workflows/test-elixir.yml",
          ].includes(path),
      ),
    image,
    actions: paths.some(
      (path) =>
        /^\.github\/(workflows|actions)\//.test(path) ||
        /^\.github\/(actionlint|zizmor)\.ya?ml$/.test(path) ||
        /^zizmor\.ya?ml$/.test(path),
    ),
  };
}

async function detectChanges({ github, context, core }) {
  try {
    let files;
    if (context.eventName === "pull_request") {
      files = await github.paginate(github.rest.pulls.listFiles, {
        ...context.repo,
        pull_number: context.payload.pull_request.number,
        per_page: 100,
      });
      // The PR files endpoint returns at most 3,000 files.
      if (files.length >= 3000) return { ...all };
    } else if (
      context.eventName === "push" &&
      context.ref === "refs/heads/main" &&
      context.payload.before &&
      !/^0+$/.test(context.payload.before)
    ) {
      const { data } = await github.rest.repos.compareCommitsWithBasehead({
        ...context.repo,
        basehead: `${context.payload.before}...${context.payload.after}`,
        per_page: 100,
      });
      files = data.files;
      // Compare responses cap the file list at 300, regardless of pagination.
      if (!files || files.length >= 300) return { ...all };
    } else {
      return { ...all };
    }
    return classifyChanges(
      files.flatMap(({ filename, previous_filename }) =>
        previous_filename ? [filename, previous_filename] : [filename],
      ),
    );
  } catch {
    core?.warning(
      "Change detection failed; running all checks and publication candidates.",
    );
    return { ...all };
  }
}

module.exports = { classifyChanges, detectChanges };
