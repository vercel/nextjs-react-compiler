import { Octokit } from 'octokit';

export const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN });

export const [owner, repo] = process.env.GITHUB_REPOSITORY!.split('/');
