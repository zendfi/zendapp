/// Wallet key derivation function constants.
///
/// All wallet encryption operations (PIN backup and NationalID recovery packet)
/// use these parameters. They are stored alongside every encrypted record so that
/// future parameter upgrades can be detected and handled transparently.
///
/// CHANGING THESE VALUES is a breaking change for any user whose keypair was
/// encrypted with the previous values. A migration path is required.
class WalletKdf {
  // ── Algorithm ─────────────────────────────────────────────────────────────

  static const String algorithm = 'argon2id';

  // ── Argon2id parameters ──────────────────────────────────────────────────
  //
  // t=1, m=65536 is OWASP's minimum recommendation for interactive logins.
  // The memory cost (64 MB) is the primary brute-force deterrent — it defeats
  // GPU parallelism regardless of t. Reducing t from 3 → 1 cuts pure-Dart
  // unlock time from ~9s → ~3s with no meaningful security regression.
  // See: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html
  //
  // Memory cost:  64 MB (65536 KiB) — forces DRAM bandwidth as the bottleneck
  // Time cost:    1 pass             — reduced from 3; still OWASP-compliant
  // Parallelism:  1 thread           — simplest for single-user operation
  // Output:       32 bytes (256-bit) — used directly as AES-256-GCM key

  static const int mCost = 65536;  // KiB (64 MB)
  static const int tCost = 1;      // reduced from 3 → ~3s on mid-range Android
  static const int pCost = 1;
  static const int hashLen = 32;   // bytes → AES-256 key

  // ── DB / export versioning ────────────────────────────────────────────────
  //
  // encryption_version stored in the encrypted_keys table and in export JSON.
  //   2 = PBKDF2-HMAC-SHA256 / 100k iterations (wallet-security-v2, legacy)
  //   3 = Argon2id, m=65536, t=3, p=1 (previous)
  //   4 = Argon2id, m=65536, t=1, p=1 (current — faster unlock, same memory cost)

  static const int encryptionVersion = 4;

  // ── Serialised param blocks ───────────────────────────────────────────────

  /// KDF params as a JSON-serialisable map — stored in `key_metadata.kdf`
  /// in the DB and in the `kdf` block of the export JSON.
  static Map<String, dynamic> get paramsJson => {
        'algorithm': algorithm,
        'm_cost': mCost,
        't_cost': tCost,
        'p_cost': pCost,
      };

  /// Full `key_metadata` object written to the DB `key_metadata` JSONB column.
  static Map<String, dynamic> get keyMetadata => {
        'kdf': paramsJson,
      };

  // ── Private constructor ───────────────────────────────────────────────────

  const WalletKdf._();
}
