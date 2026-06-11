import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

export interface FileAddition {
  path: string;
  contents: string; // base64
}

export interface FileDeletion {
  path: string;
}

export interface FileChanges {
  additions: FileAddition[];
  deletions: FileDeletion[];
}

export function collectFileChanges(dir: string, base: string): FileChanges {
  execSync(`git add -A ${dir}`);

  const diffRaw = execSync(`git diff-index --cached --name-status -z ${base}`).toString();
  const tokens = diffRaw.split('\0');
  const additions: FileAddition[] = [];
  const deletions: FileDeletion[] = [];

  let i = 0;
  while (i < tokens.length) {
    const status = tokens[i];
    if (!status) { i++; continue; }
    const code = status[0];
    if (code === 'A' || code === 'M' || code === 'T') {
      const p = tokens[++i]; i++;
      additions.push({ path: p, contents: readFileSync(p).toString('base64') });
    } else if (code === 'D') {
      deletions.push({ path: tokens[++i] }); i++;
    } else if (code === 'R' || code === 'C') {
      const oldPath = tokens[++i];
      const newPath = tokens[++i]; i++;
      if (code === 'R') deletions.push({ path: oldPath });
      additions.push({ path: newPath, contents: readFileSync(newPath).toString('base64') });
    } else {
      i++;
    }
  }

  return { additions, deletions };
}
