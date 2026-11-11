// Pay-to-read decryption for the Zend app (AppKit primitives R11, design D11 "Reading").
//
// Built into `web/zend_seal.js` (loaded into the Zend web app's own page) and
// `assets/seal/zend_seal.js` (inlined into a hidden webview on mobile) by `npm run build`.
// Dart side: lib/src/services/unlock_reader.dart and seal_engine_{web,io}.dart.
// ZApp pages never load this file and never see what it holds.
//
// The bundle does no networking and no signing of its own. The host (Zend's Dart code) provides:
// - `sign(messageB64)`: the person's zkLogin signature over a personal message, base64.
// - `fetchKey(bodyJson, headers)`: posts to Zend's key relay, returns { status, headers, body }.
// Key-server details and the `seal_approve` transaction come from Zend's backend with each call.
//
// What stays in here, in memory only: the session key (valid 30 minutes for the zend_unlock
// package) and the keys fetched with it. Keys come back encrypted to a one-time key made here, so
// the relay can't read them.

import { EncryptedObject, ExpiredSessionKeyError, NoAccessError, SealClient, SessionKey } from '@mysten/seal';
import { fromBase64, toBase64 } from '@mysten/sui/utils';

export interface Host {
  sign(messageB64: string): Promise<string>;
  fetchKey(bodyJson: string, headers: Record<string, string>): Promise<{ status: number; headers: Record<string, string>; body: string }>;
}

export interface KeyServers {
  /** The key server committee's object id (committee servers only; requests go through `fetchKey`). */
  objectId: string;
  /** BCS of the key server object's contents, base64. */
  objectBcs: string;
  /** BCS of its `KeyServerV<version>` dynamic field value, base64. */
  fieldBcs: string;
  /** The version the field is stored under (2 today). */
  version: number;
}

export interface DecryptRequest {
  packageId: string;
  /** The listing the caller's app sold; the ciphertext's id must start with it. */
  listingId: string;
  address: string;
  keyServers: KeyServers;
  /** `seal_approve` transaction kind bytes from the backend, base64. */
  txKind: string;
  /** The encrypted object, base64. */
  data: string;
}

export class ZendSealError extends Error {
  constructor(public code: 'bad_data' | 'wrong_item' | 'no_access' | 'expired' | 'unavailable', message: string) {
    super(message);
  }
}

// Android System WebView before 92 has no randomUUID (the SDK uses it for request ids).
const c = globalThis.crypto as any;
if (c && typeof c.randomUUID !== 'function') {
  c.randomUUID = () => {
    const b = c.getRandomValues(new Uint8Array(16));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    const h = Array.from(b, (x: number) => x.toString(16).padStart(2, '0')).join('');
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  };
}

const TTL_MIN = 30;
const RELAY = 'https://relay.invalid';

let host: Host | null = null;
const sessions = new Map<string, SessionKey>();
const clients = new Map<string, SealClient>();

export function setHost(h: Host) {
  host = h;
}

function needHost(): Host {
  if (!host) throw new ZendSealError('unavailable', 'zendSeal host not set');
  return host;
}

const hexOf = (id: string) => id.toLowerCase().replace(/^0x/, '').padStart(64, '0');

/** The package and id an encrypted object was made for, without decrypting it. */
export function inspect(dataB64: string): { packageId: string; id: string } {
  try {
    const o = EncryptedObject.parse(fromBase64(dataB64));
    return { packageId: '0x' + hexOf(o.packageId), id: o.id };
  } catch {
    throw new ZendSealError('bad_data', "That content can't be opened");
  }
}

/** Answers only the reads the SDK makes, from what Zend's backend sent. */
function readerFor(packageId: string, ks: KeyServers) {
  const core = {
    async getObject({ objectId }: { objectId: string }) {
      if (hexOf(objectId) === hexOf(packageId)) return { object: { objectId, version: '1' } };
      if (hexOf(objectId) === hexOf(ks.objectId)) {
        return { object: { objectId, content: fromBase64(ks.objectBcs) } };
      }
      throw new ZendSealError('unavailable', `unexpected object read ${objectId}`);
    },
    async getDynamicField({ parentId }: { parentId: string }) {
      if (hexOf(parentId) !== hexOf(ks.objectId)) {
        throw new ZendSealError('unavailable', `unexpected field read ${parentId}`);
      }
      return { dynamicField: { value: { bcs: fromBase64(ks.fieldBcs) } } };
    },
  };
  return { core } as any;
}

/** `fetch` for the SDK: key requests go to the host's relay, nothing else is allowed. */
async function relayFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const url = String(input instanceof Request ? input.url : input);
  if (!url.endsWith('/v1/fetch_key')) throw new ZendSealError('unavailable', `unexpected request ${url}`);
  const headers: Record<string, string> = {};
  new Headers(init?.headers).forEach((v, k) => (headers[k] = v));
  const r = await needHost().fetchKey(String(init?.body ?? ''), headers);
  return new Response(r.body, { status: r.status, headers: r.headers });
}

function clientFor(packageId: string, ks: KeyServers): SealClient {
  const k = `${hexOf(packageId)}|${hexOf(ks.objectId)}|${ks.objectBcs.length}|${ks.fieldBcs}`;
  let c = clients.get(k);
  if (!c) {
    c = new SealClient({
      suiClient: readerFor(packageId, ks),
      serverConfigs: [{ objectId: ks.objectId, weight: 1, aggregatorUrl: RELAY }],
      verifyKeyServers: false,
      fetch: relayFetch,
      timeout: 15_000,
    });
    clients.set(k, c);
  }
  return c;
}

async function sessionFor(address: string, packageId: string, ks: KeyServers): Promise<SessionKey> {
  const k = `${address.toLowerCase()}|${hexOf(packageId)}`;
  const s = sessions.get(k);
  if (s && !s.isExpired()) return s;
  const h = needHost();
  const fresh = await SessionKey.create({
    address,
    packageId,
    ttlMin: TTL_MIN,
    suiClient: readerFor(packageId, ks),
    signer: {
      async signPersonalMessage(bytes: Uint8Array) {
        return { bytes: toBase64(bytes), signature: await h.sign(toBase64(bytes)) };
      },
    } as any,
  });
  sessions.set(k, fresh);
  return fresh;
}

/** Decrypts `data` for the person, after checking it belongs to the caller's listing. */
export async function decrypt(req: DecryptRequest): Promise<string> {
  const { packageId, id } = inspect(req.data);
  if (hexOf(packageId) !== hexOf(req.packageId) || !id.toLowerCase().startsWith(hexOf(req.listingId))) {
    throw new ZendSealError('wrong_item', "That content isn't part of this item");
  }
  const client = clientFor(req.packageId, req.keyServers);
  const run = async () =>
    client.decrypt({
      data: fromBase64(req.data),
      sessionKey: await sessionFor(req.address, req.packageId, req.keyServers),
      txBytes: fromBase64(req.txKind),
    });
  try {
    let out: Uint8Array;
    try {
      out = await run();
    } catch (e) {
      if (!(e instanceof ExpiredSessionKeyError)) throw e;
      sessions.delete(`${req.address.toLowerCase()}|${hexOf(req.packageId)}`);
      out = await run();
    }
    return toBase64(out);
  } catch (e) {
    if (e instanceof ZendSealError) throw e;
    if (e instanceof NoAccessError) throw new ZendSealError('no_access', "You haven't unlocked this yet");
    throw new ZendSealError('unavailable', (e as Error)?.message ?? String(e));
  }
}

/** Drops the session key and fetched keys (sign-out). */
export function forget() {
  sessions.clear();
  clients.clear();
}

// ===== String-only interface for Dart =====
//
// Dart only exchanges JSON strings with the bundle, on web (js_interop) and mobile (webview)
// alike, so no JS error objects or typed values cross the boundary.

/** Runs `decrypt`, `inspect` or `forget`; resolves to `{ok:true,value}` or `{ok:false,error:{code,message}}`. */
export async function call(method: string, argsJson: string): Promise<string> {
  try {
    const args = JSON.parse(argsJson || '{}');
    const value =
      method === 'decrypt' ? await decrypt(args) :
      method === 'inspect' ? inspect(args.data) :
      method === 'forget' ? forget() :
      (() => { throw new ZendSealError('unavailable', `unknown method ${method}`); })();
    return JSON.stringify({ ok: true, value: value ?? null });
  } catch (e) {
    const error = e instanceof ZendSealError ? { code: e.code, message: e.message } : { code: 'unavailable', message: String((e as Error)?.message ?? e) };
    return JSON.stringify({ ok: false, error });
  }
}

/** Host whose `fetchKey` takes `{"body","headers"}` and returns `{"status","headers","body"}`, as JSON. */
export function setJsonHost(h: { sign(messageB64: string): Promise<string>; fetchKey(argsJson: string): Promise<string> }) {
  setHost({
    sign: (m) => h.sign(m),
    fetchKey: async (body, headers) => JSON.parse(await h.fetchKey(JSON.stringify({ body, headers }))),
  });
}

// ===== Message bridge for the mobile webview =====
//
// Dart calls `zendSealCall(id, method, argsJson)`; results go back as
// `ZendSealHost.postMessage({t:'res', id, result})` with `result` from `call`. Host callbacks go
// out as `{t:'cb', id, kind, args}` and Dart answers with `zendSealReply(id, ok, valueJson)`.

type Channel = { postMessage(s: string): void };
const pending = new Map<number, { ok: (v: any) => void; no: (e: any) => void }>();
let nextCb = 1;

function callHost(ch: Channel, kind: string, args: unknown): Promise<any> {
  const id = nextCb++;
  return new Promise((ok, no) => {
    pending.set(id, { ok, no });
    ch.postMessage(JSON.stringify({ t: 'cb', id, kind, args }));
  });
}

export function attach(ch: Channel) {
  setHost({
    sign: (m) => callHost(ch, 'sign', { message: m }),
    fetchKey: (body, headers) => callHost(ch, 'fetchKey', { body, headers }),
  });
  const g = globalThis as any;
  g.zendSealReply = (id: number, ok: boolean, valueJson: string) => {
    const p = pending.get(id);
    if (!p) return;
    pending.delete(id);
    const v = JSON.parse(valueJson);
    ok ? p.ok(v) : p.no(new ZendSealError('unavailable', String(v?.message ?? v)));
  };
  g.zendSealCall = async (id: number, method: string, argsJson: string) => {
    ch.postMessage(JSON.stringify({ t: 'res', id, result: await call(method, argsJson) }));
  };
  ch.postMessage(JSON.stringify({ t: 'ready' }));
}
