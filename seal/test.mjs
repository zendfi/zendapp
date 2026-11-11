// Runs the built bundle (web/zend_seal.js) against the real mainnet key-server committee data in
// fixtures/committee.json, with a fake host standing in for Dart and Zend's relay. Checks what
// the relay receives is signed correctly and that errors map to the bundle's codes. The key
// servers themselves aren't reached (that needs the published package and an Enoki key).
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { SealClient } from '@mysten/seal';
import { bcs } from '@mysten/sui/bcs';
import { Ed25519Keypair, Ed25519PublicKey } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';
import { fromBase64, toBase64, toHex } from '@mysten/sui/utils';
import { verifyPersonalMessageSignature } from '@mysten/sui/verify';

const zendSeal = new Function(readFileSync('../web/zend_seal.js', 'utf8') + '\nreturn zendSeal;')();

const fx = JSON.parse(readFileSync('fixtures/committee.json', 'utf8')).data.object;
const COMMITTEE = '0x686098f1439237fff9f36b99c7329683c22979d2005c2465cb891acb012a7595';
const keyServers = { objectId: COMMITTEE, objectBcs: fx.asMoveObject.contents.bcs, fieldBcs: fx.dynamicField.value.bcs, version: 2 };
const PKG = '0x' + '5e'.repeat(32);
const LISTING = '0x' + 'a1'.repeat(32);
const OTHER = '0x' + 'b2'.repeat(32);

const user = Ed25519Keypair.generate();
const address = user.toSuiAddress();

// Ciphertext made the way a ZApp server would, with the real committee public key.
const reader = { core: {
  getObject: async ({ objectId }) => objectId === PKG ? { object: { version: '1' } } : { object: { content: fromBase64(keyServers.objectBcs) } },
  getDynamicField: async () => ({ dynamicField: { value: { bcs: fromBase64(keyServers.fieldBcs) } } }),
} };
const sealer = new SealClient({ suiClient: reader, serverConfigs: [{ objectId: COMMITTEE, weight: 1, aggregatorUrl: 'https://x.invalid' }] });
const enc = async (listing, suffix) => toBase64((await sealer.encrypt({
  threshold: 1, packageId: PKG, id: listing.slice(2) + toHex(new TextEncoder().encode(suffix)),
  data: new TextEncoder().encode('chapter two'),
})).encryptedObject);
const data = await enc(LISTING, '/ch2');
const otherData = await enc(OTHER, '');

const tx = new Transaction();
tx.moveCall({ target: `${PKG}::unlock::seal_approve`, arguments: [
  tx.pure.vector('u8', fromBase64(toBase64(new Uint8Array(32).fill(0xa1)))),
  tx.objectRef({ objectId: '0x' + 'cc'.repeat(32), version: '7', digest: 'GvnqnAzX8uFiBJ5x1T4DZFLDFY2V3iQMMm1Hhqa6hEK4' }),
] });
const txKind = toBase64(await tx.build({ onlyTransactionKind: true }));

let signs = 0;
let reply = { status: 403, body: { error: 'NoAccess', message: 'no' } };
const seen = [];
zendSeal.setHost({
  async sign(messageB64) {
    signs++;
    const msg = new TextDecoder().decode(fromBase64(messageB64));
    assert.match(msg, new RegExp(`^Accessing keys of package ${PKG} for 30 mins from `));
    return (await user.signPersonalMessage(fromBase64(messageB64))).signature;
  },
  async fetchKey(bodyJson, headers) {
    const body = JSON.parse(bodyJson);
    seen.push({ body, headers });
    const r = reply;
    reply = { status: 403, body: { error: 'NoAccess', message: 'no' } };
    return { status: r.status, headers: { 'content-type': 'application/json' }, body: JSON.stringify(r.body) };
  },
});
const req = { packageId: PKG, listingId: LISTING, address, keyServers, txKind, data };
const code = async (p) => { try { await p; return 'ok'; } catch (e) { return e.code ?? e.message; } };

// 1. Content from another listing is refused before anything is signed or sent.
assert.equal(zendSeal.inspect(data).id.startsWith(LISTING.slice(2)), true);
assert.equal(await code(zendSeal.decrypt({ ...req, data: otherData })), 'wrong_item');
assert.equal(await code(zendSeal.decrypt({ ...req, data: 'AAAA' })), 'bad_data');
assert.equal(signs + seen.length, 0);

// 2. A real request: one signature, a well-formed relay body, NoAccess mapped.
assert.equal(await code(zendSeal.decrypt(req)), 'no_access');
assert.equal(signs, 1);
const { body, headers } = seen[0];
assert.equal(headers['client-sdk-type'], 'typescript');
assert.equal(body.ptb, toBase64(fromBase64(txKind).slice(1)));
assert.equal(body.certificate.user, address);
assert.equal(body.certificate.ttl_min, 30);
const cert = body.certificate;
const certMsg = `Accessing keys of package ${PKG} for 30 mins from ${new Date(cert.creation_time).toISOString().slice(0, 19).replace('T', ' ')} UTC, session key ${cert.session_vk}`;
await verifyPersonalMessageSignature(new TextEncoder().encode(certMsg), cert.signature, { address });
const signed = bcs.struct('RequestFormat', { ptb: bcs.byteVector(), encKey: bcs.byteVector(), encVerificationKey: bcs.byteVector() })
  .serialize({ ptb: fromBase64(body.ptb), encKey: fromBase64(body.enc_key), encVerificationKey: fromBase64(body.enc_verification_key) }).toBytes();
assert.equal(await new Ed25519PublicKey(fromBase64(cert.session_vk)).verify(signed, fromBase64(body.request_signature)), true);

// 3. The session key is reused: no second signature, and a fresh one-time key per request.
assert.equal(await code(zendSeal.decrypt(req)), 'no_access');
assert.equal(signs, 1);
assert.notEqual(seen[1].body.enc_key, seen[0].body.enc_key);

// 4. A rejected certificate gets a new session key once.
reply = { status: 403, body: { error: 'InvalidCertificate', message: 'old' } };
assert.equal(await code(zendSeal.decrypt(req)), 'no_access');
assert.equal(signs, 2);
assert.notEqual(seen[3].body.certificate.session_vk, seen[2].body.certificate.session_vk);

// 5. The relay being down is "unavailable", not "no access".
reply = { status: 502, body: 'bad gateway' };
assert.equal(await code(zendSeal.decrypt(req)), 'unavailable');

// 6. forget() drops the session key.
zendSeal.forget();
await code(zendSeal.decrypt(req));
assert.equal(signs, 3);

// 7. Web interface: JSON strings only, through setJsonHost / call.
zendSeal.forget();
let jsonSigns = 0;
zendSeal.setJsonHost({
  async sign(m) { jsonSigns++; return (await user.signPersonalMessage(fromBase64(m))).signature; },
  async fetchKey(argsJson) {
    const { body, headers } = JSON.parse(argsJson);
    assert.equal(typeof body, 'string');
    assert.equal(headers['client-sdk-type'], 'typescript');
    return JSON.stringify({ status: 403, headers: { 'content-type': 'application/json' }, body: JSON.stringify({ error: 'NoAccess', message: 'no' }) });
  },
});
assert.deepEqual(JSON.parse(await zendSeal.call('decrypt', JSON.stringify(req))), { ok: false, error: { code: 'no_access', message: "You haven't unlocked this yet" } });
assert.equal(jsonSigns, 1);
assert.equal(JSON.parse(await zendSeal.call('inspect', JSON.stringify({ data }))).value.id.startsWith(LISTING.slice(2)), true);
assert.equal(JSON.parse(await zendSeal.call('nope', '{}')).error.code, 'unavailable');

// 8. Mobile interface: the webview message bridge, with this test playing Dart.
zendSeal.forget();
const results = new Map();
let bridgeSigns = 0;
let ready = false;
const channel = { postMessage(s) {
  const m = JSON.parse(s);
  if (m.t === 'ready') ready = true;
  if (m.t === 'res') results.get(m.id)(m.result);
  if (m.t === 'cb') (async () => {
    let value;
    if (m.kind === 'sign') { bridgeSigns++; value = (await user.signPersonalMessage(fromBase64(m.args.message))).signature; }
    else value = { status: 403, headers: { 'content-type': 'application/json' }, body: JSON.stringify({ error: 'NoAccess', message: 'no' }) };
    globalThis.zendSealReply(m.id, true, JSON.stringify(value));
  })();
} };
zendSeal.attach(channel);
assert.equal(ready, true);
const viaBridge = await new Promise((ok) => { results.set(41, ok); globalThis.zendSealCall(41, 'decrypt', JSON.stringify(req)); });
assert.equal(JSON.parse(viaBridge).error.code, 'no_access');
assert.equal(bridgeSigns, 1);

console.log('zend_seal: all checks passed');
