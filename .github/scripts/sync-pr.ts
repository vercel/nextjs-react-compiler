import { execSync } from 'node:child_process';
import { collectFileChanges } from './collect-file-changes.ts';
import { octokit, owner, repo } from './github-api.ts';

const branch = process.env.BRANCH!;
const upstreamRef = process.env.UPSTREAM_REF!;
const reactSha = process.env.REACT_SHA ?? 'unknown';
const swcSha = process.env.SWC_SHA ?? 'unknown';
const baseSha = execSync('git rev-parse origin/main').toString().trim();

const { additions, deletions } = collectFileChanges('react-compiler', 'origin/main');

if (additions.length === 0 && deletions.length === 0) {
  console.log('No changes vs origin/main — skipping PR');
  process.exit(0);
}

const commitHeadline = `vendor: react-compiler @ ${reactSha} swc @ ${swcSha}`;

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
      headline: commitHeadline,
      body: `Synced from react/react ref \`${upstreamRef}\`.`,
    },
    fileChanges: { additions, deletions },
    expectedHeadOid: baseSha,
  },
});

await octokit.rest.pulls.create({
  owner, repo,
  title: commitHeadline,
  body: `Automated sync. react/react ref: \`${upstreamRef}\`, react SHA: \`${reactSha}\`, swc SHA: \`${swcSha}\`.`,
  head: branch,
  base: 'main',
});
