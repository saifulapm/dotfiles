// The repo keeps comments to one line: the files that rule covers, and the lines of one text that break it.
export const covered = (f) => /\.(qml|mjs|sh|kdl|tmpl|service|toml)$|^bin\//.test(f) && !f.startsWith('.claude/');

// In C a leading # is the preprocessor, not a comment.
const isComment = (f, line) => (f.endsWith('.c') ? /^\s*\/\//.test(line) : /^\s*(\/\/|#)/.test(line) && !/^#!/.test(line) && !/^\s*# shellcheck /.test(line));

// The 1-based numbers of each line of TEXT that is a comment right after another.
export function doubled(f, text) {
  const lines = text.split('\n');
  const found = [];
  for (let i = 1; i < lines.length; i++) if (isComment(f, lines[i]) && isComment(f, lines[i - 1])) found.push(i + 1);
  return found;
}
