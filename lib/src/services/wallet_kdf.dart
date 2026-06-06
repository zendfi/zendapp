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
  // These match the OWASP recommendations for interactive logins as of 2024,
  // and are specifically chosen to make GPU brute-force of a 6-digit PIN space
  // (10^6 candidates) take on the order of 10^8 seconds on a GPU cluster.
  //
  // Memory cost:  64 MB (65536 KiB) — forces DRAM bandwidth as the bottleneck
  // Time cost:    3 passes            — increases CPU time proportionally
  // Parallelism:  1 thread            — simplest for single-user operation
  // Output:       32 bytes (256-bit)  — used directly as AES-256-GCM key

  static const int mCost = 65536;  // KiB (64 MB)
  static const int tCost = 3;
  static const int pCost = 1;
  static const int hashLen = 32;   // bytes → AES-256 key

  // ── DB / export versioning ────────────────────────────────────────────────
  //
  // encryption_version stored in the encrypted_keys table and in export JSON.
  //   2 = PBKDF2-HMAC-SHA256 / 100k iterations (wallet-security-v2, legacy)
  //   3 = Argon2id with params below (this spec, current)

  static const int encryptionVersion = 3;

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
