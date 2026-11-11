// Builds src/zend_seal.ts into the two places the app loads it from:
//   web/zend_seal.js          (web: injected into the Zend page on first use)
//   assets/seal/zend_seal.js  (mobile: inlined into a hidden webview by seal_engine_io.dart)
import { build } from 'esbuild';
import { copyFileSync, mkdirSync, statSync } from 'node:fs';

const out = '../web/zend_seal.js';
await build({
  entryPoints: ['src/zend_seal.ts'],
  bundle: true,
  minify: true,
  format: 'iife',
  globalName: 'zendSeal',
  target: ['es2020', 'safari15'],
  platform: 'browser',
  legalComments: 'eof',
  outfile: out,
});
mkdirSync('../assets/seal', { recursive: true });
copyFileSync(out, '../assets/seal/zend_seal.js');
console.log(`zend_seal.js ${(statSync(out).size / 1024).toFixed(0)} KB`);
