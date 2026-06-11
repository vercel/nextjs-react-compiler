import { execSync } from 'node:child_process';
import { collectFileChanges } from './collect-file-changes.ts';
import { octokit, owner, repo } from './github-api.ts';

const version = process.env.VERSION!;
const allowEmpty = process.env.ALLOW_EMPTY === 'true';
const branch = `release/v${version}`;
const baseSha = execSync('git rev-parse HEAD').toString().trim();

const { additions, deletions } = collectFileChanges('react-compiler', 'HEAD');

const hasChanges = additions.length > 0 || deletions.length > 0;
if (!hasChanges && !allowEmpty) {
  console.error('No version changes to commit');
  process.exit(1);
}

// Re-runs (e.g. testing) may leave the branch behind; delete-then-create
// is simpler than updateRef + force-push and keeps the branch fresh.
try {
  await octokit.rest.git.deleteRef({ owner, repo, ref: `heads/${branch}` });
} catch (err: any) {
  if (err.status !== 422 && err.status !== 404) throw err;
}

await octokit.rest.git.createRef({
  owner, repo,
  ref: `refs/heads/${branch}`,
  sha: baseSha,
});

if (hasChanges) {
  await octokit.graphql(`
    mutation CreateCommitOnBranch($input: CreateCommitOnBranchInput!) {
      createCommitOnBranch(input: $input) {
        commit { oid }
      }
    }
  `, {
    input: {
      branch: { repositoryNameWithOwner: `${owner}/${repo}`, branchName: branch },
      message: { headline: `release: bump to ${version}` },
      fileChanges: { additions, deletions },
      expectedHeadOid: baseSha,
    },
  });
}

let body = 'Version bump via `just codemod`. Merge this, then run the **Publish Crates** workflow against `main`.';
if (allowEmpty && !hasChanges) {
  body += '\n\n**Warning:** created with allow-empty — no files changed. For testing only.';
}

await octokit.rest.pulls.create({
  owner, repo,
  title: `release: bump to ${version}`,
  body,
  head: branch,
  base: 'main',
});
