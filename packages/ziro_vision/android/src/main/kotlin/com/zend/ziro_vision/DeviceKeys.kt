package com.zend.ziro_vision

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import kotlinx.coroutines.suspendCancellableCoroutine
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Hardware P-256 device key (Keystore, StrongBox when present) and Play Integrity. */
class DeviceKeys(private val ctx: Context) {
    private val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private var provider: StandardIntegrityManager.StandardIntegrityTokenProvider? = null

    private fun b64(b: ByteArray) = Base64.encodeToString(b, Base64.NO_WRAP)

    /** SEC1 uncompressed point (65 bytes). */
    private fun sec1(pk: ECPublicKey): ByteArray {
        fun fixed(v: java.math.BigInteger): ByteArray {
            val raw = v.toByteArray()
            return when {
                raw.size == 32 -> raw
                raw.size > 32 -> raw.copyOfRange(raw.size - 32, raw.size)
                else -> ByteArray(32 - raw.size) + raw
            }
        }
        return byteArrayOf(0x04) + fixed(pk.w.affineX) + fixed(pk.w.affineY)
    }

    private fun generate(alias: String, challenge: ByteArray, strongBox: Boolean) {
        val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setAttestationChallenge(challenge)
            .apply { if (strongBox && Build.VERSION.SDK_INT >= 28) setIsStrongBoxBacked(true) }
            .build()
        val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
        kpg.initialize(spec)
        kpg.generateKeyPair()
    }

    fun create(alias: String, challenge: ByteArray): Map<String, Any?> {
        if (ks.containsAlias(alias)) ks.deleteEntry(alias)
        val hasStrongBox = Build.VERSION.SDK_INT >= 28 &&
            ctx.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        try {
            generate(alias, challenge, hasStrongBox)
        } catch (e: Exception) {
            if (hasStrongBox && (Build.VERSION.SDK_INT >= 28 && e is StrongBoxUnavailableException || e.cause is StrongBoxUnavailableException)) {
                generate(alias, challenge, false)
            } else throw e
        }
        val chain = ks.getCertificateChain(alias) ?: throw IllegalStateException("no attestation chain")
        val pk = chain[0].publicKey as ECPublicKey
        return mapOf(
            "public_key" to b64(sec1(pk)),
            "android" to mapOf("key_attestation_chain" to chain.map { b64(it.encoded) }),
        )
    }

    /** SHA256withECDSA over [data], DER. */
    fun sign(alias: String, data: ByteArray): ByteArray {
        val key = (ks.getEntry(alias, null) as? KeyStore.PrivateKeyEntry)?.privateKey
            ?: throw IllegalStateException("no device key")
        return Signature.getInstance("SHA256withECDSA").run { initSign(key); update(data); sign() }
    }

    private suspend fun tokenProvider(): StandardIntegrityManager.StandardIntegrityTokenProvider {
        provider?.let { return it }
        val project = ctx.packageManager.getApplicationInfo(ctx.packageName, PackageManager.GET_META_DATA)
            .metaData?.getLong("com.zend.ziro.cloud_project_number", 0L) ?: 0L
        if (project == 0L) throw IllegalStateException("cloud project number missing")
        val mgr = IntegrityManagerFactory.createStandard(ctx)
        val req = StandardIntegrityManager.PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(project).build()
        val p = suspendCancellableCoroutine { c ->
            mgr.prepareIntegrityToken(req)
                .addOnSuccessListener { c.resume(it) }
                .addOnFailureListener { c.resumeWithException(it) }
        }
        provider = p
        return p
    }

    /** Warm the provider when Ziro opens so the token is quick at Charge. */
    suspend fun prepareIntegrity() { runCatching { tokenProvider() } }

    /** requestHash = base64url, no padding, of the 32-byte hash. */
    suspend fun integrityToken(requestHash: ByteArray): String {
        val p = tokenProvider()
        val hash = Base64.encodeToString(requestHash, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        val req = StandardIntegrityManager.StandardIntegrityTokenRequest.builder().setRequestHash(hash).build()
        return suspendCancellableCoroutine { c ->
            p.request(req)
                .addOnSuccessListener { c.resume(it.token()) }
                .addOnFailureListener { c.resumeWithException(it) }
        }
    }
}
