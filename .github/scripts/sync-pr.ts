import { execSync } from 'node:child_process';
import { collectFileChanges } from './collect-file-changes.ts';
import { octokit, owner, repo } from './github-api.ts';

const branch = process.env.BRANCH!;
const upstreamRef = process.env.UPSTREAM_REF!;
const baseSha = execSync('git rev-parse origin/main').toString().trim();

const { additions, deletions } = collectFileChanges('react-compiler', 'origin/main');

if (additions.length === 0 && deletions.length === 0) {
  console.log('No changes vs origin/main — skipping PR');
  process.exit(0);
}

// Extract the vendored upstream SHA from the sync commit message for the PR description.
let upstreamSha = 'unknown';
for (const msg of execSync('git log --format=%s origin/main..HEAD').toString().trim().split('\n')) {
  const m = msg.match(/\b([0-9a-f]{40})\b/);
  if (m) { upstreamSha = m[1]; break; }
}

await octokit.rest.git.createRef({
  owner, repo,
  ref: `refs/heads/${branch}`,
  sha: baseSha,
});

await octokit.graphql(`
  mutation CreateCommitOnBranch($input: CreateCommitOnBranchInput!) {
    createCommitOnBranch(input: $input) {
      commit { oid }
    }
  }
`, {
  input: {
    branch: { repositoryNameWithOwner: `${owner}/${repo}`, branchName: branch },
    message: {
      headline: 'vendor: sync react-compiler upstream',
      body: `Ref: \`${upstreamRef}\`, upstream commit: \`${upstreamSha}\`.`,
    },
    fileChanges: { additions, deletions },
    expectedHeadOid: baseSha,
  },
});

await octokit.rest.pulls.create({
  owner, repo,
  title: 'vendor: sync react-compiler upstream',
  body: `Automated sync via \`just sync && just codemod\`. Ref: \`${upstreamRef}\`, upstream commit: \`${upstreamSha}\`.`,
  head: branch,
  base: 'main',
});
