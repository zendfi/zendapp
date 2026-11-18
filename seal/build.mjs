// Builds src/zend_seal.ts into the two places the app loads it from:
//   web/zend_seal.js          (web: injected into the Zend page on first use)
//   assets/seal/zend_seal.js  (mobile: inlined into a hidden webview by seal_engine_io.dart)
// and src/zend_argon2.ts into web/zend_argon2.js (web only: cash codes; native uses Dart).
import { build } from 'esbuild';
import { copyFileSync, mkdirSync, statSync } from 'node:fs';

const common = {
  bundle: true,
  minify: true,
  format: 'iife',
  target: ['es2020', 'safari15'],
  platform: 'browser',
  legalComments: 'eof',
};

const out = '../web/zend_seal.js';
await build({ ...common, entryPoints: ['src/zend_seal.ts'], globalName: 'zendSeal', outfile: out });
mkdirSync('../assets/seal', { recursive: true });
copyFileSync(out, '../assets/seal/zend_seal.js');
console.log(`zend_seal.js ${(statSync(out).size / 1024).toFixed(0)} KB`);

const argon = '../web/zend_argon2.js';
await build({ ...common, entryPoints: ['src/zend_argon2.ts'], globalName: 'zendArgon2', outfile: argon });
console.log(`zend_argon2.js ${(statSync(argon).size / 1024).toFixed(0)} KB`);
