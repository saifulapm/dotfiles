// A colorscheme read from colorschemes/<name>.toml and worn on the one design, as the shell reads its tokens; node only.
import { readFileSync, existsSync } from 'node:fs';
import { parseToml } from './toml.mjs';
import { qtTokens } from './theme.mjs';
import { validateColorscheme, designOf } from './colorscheme.mjs';

export const SCHEMES = new URL('../../colorschemes/', import.meta.url).pathname;

// The design's tokens for a scheme; throws, naming it, when there is no such file.
export function loadScheme(name) {
  const file = `${SCHEMES}${name}.toml`;
  if (!existsSync(file)) throw new Error(`colorscheme ${name}: no such colorscheme`);
  return designOf(validateColorscheme(parseToml(readFileSync(file, 'utf8'))));
}

export const schemeTokens = (name) => qtTokens(loadScheme(name));
