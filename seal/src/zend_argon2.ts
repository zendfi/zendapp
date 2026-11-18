// Argon2id for the web app, where pure-Dart Argon2 is far too slow (64-bit integer maths
// compiled to JS). Used to turn a cash code into its link key; see lib/src/core/cash_code.dart.
// The parameters are fixed here and must match `CashCode` on native: 64 MiB, 1 pass, 1 lane,
// 32-byte output, Argon2 version 1.3.
import { argon2id } from 'hash-wasm';

export async function derive(password: Uint8Array, salt: Uint8Array): Promise<Uint8Array> {
  return argon2id({
    password,
    salt,
    parallelism: 1,
    iterations: 1,
    memorySize: 65536,
    hashLength: 32,
    outputType: 'binary',
  });
}
