// Loads one of the core's plain-JS files (the ones QML imports with
// `import "X.js" as X`) into a fresh vm context, the way QML sees it: its
// top-level functions and vars become the context's properties.
import fs from 'node:fs';
import vm from 'node:vm';

export function load(relativePath) {
  const url = new URL(`../${relativePath}`, import.meta.url);
  const context = {};
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(url, 'utf8'), context, { filename: relativePath });
  return context;
}

// Values built inside the vm carry its own Object/Array prototypes, which
// deepStrictEqual treats as different. Round-trip through JSON first.
export const plain = (value) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)));
