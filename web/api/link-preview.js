// Link previews for app.usezend.app (Vercel Edge Function).
//
// WhatsApp, iMessage, Telegram and the like don't run the app; they read the HTML <head>.
// Every path serves the same Flutter index.html, titled just "Zend", so a money link showed
// nothing about the money. vercel.json rewrites /z/:id, /a/:id and /cash here; this fetches
// the link's public preview from the API and puts "Kemi sent you $20" (with Kemi's photo)
// into the head. People get the same page, so the app loads exactly as before.
//
// Never sees a link key: the key (and a cash code) sit after '#', which no browser or
// crawler sends. Cash previews stay generic on purpose; what a cash link holds is shown
// only to someone with its code.
//
// Copy is user-facing: keep it free of crypto words (.kiro/steering/user-facing-language.md).
// Amounts come preformatted from the API (`amount_label`, in the sender's currency).

export const config = { runtime: 'edge' };

const API_BASE = 'https://api.usezend.app';
const API_TIMEOUT_MS = 1500;

function esc(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

async function fetchJson(path) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), API_TIMEOUT_MS);
  try {
    const res = await fetch(`${API_BASE}${path}`, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    });
    return res.ok ? await res.json() : null;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

function realName(name) {
  const n = typeof name === 'string' ? name.trim() : '';
  return n && n !== 'Someone' ? n : null;
}

function photo(url) {
  return typeof url === 'string' && url.startsWith('https://') ? url : null;
}

function quoted(memo) {
  const m = typeof memo === 'string' ? memo.trim() : '';
  // GIF notes are stored as "gif:<id>"; they mean nothing as text.
  if (!m || m.startsWith('gif:')) return '';
  return `“${m.length > 120 ? `${m.slice(0, 117)}…` : m}” `;
}

/** Title, description and image for one link, or null to keep the defaults. */
async function previewFor(kind, id) {
  if (kind === 'cash') {
    return {
      title: "You've got Zend cash",
      description: 'Open it to collect it on Zend.',
      image: null,
    };
  }
  if (kind === 'give') {
    const v = await fetchJson(`/api/zend/v2/zlinks/give/${encodeURIComponent(id)}`);
    if (!v) return null;
    const name = realName(v.sender_name);
    const amount = v.amount_label || 'money';
    const who = name || 'Someone';
    const closed = {
      claimed: 'This money has already been received.',
      returned: `${who} took this back.`,
      expired: 'This link has expired.',
    }[v.status];
    return {
      title: closed
        ? `${who} sent you money on Zend`
        : name ? `${name} sent you ${amount}` : `You've been sent ${amount}`,
      description: closed || `${quoted(v.memo)}Open it to collect it on Zend.`,
      image: photo(v.sender_avatar),
    };
  }
  if (kind === 'ask') {
    const v = await fetchJson(`/api/zend/v2/zlinks/ask/${encodeURIComponent(id)}`);
    if (!v) return null;
    const name = realName(v.payee_name) || 'Someone';
    const amount = v.amount_label || 'money';
    const open = v.status === 'active';
    return {
      title: open ? `${name} is asking for ${amount}` : `${name} asked for money on Zend`,
      description: open ? `${quoted(v.memo)}Pay it on Zend.` : 'This request is closed.',
      image: photo(v.payee_avatar),
    };
  }
  return null;
}

function headTags({ title, description, image, url, fallbackImage }) {
  const img = image || fallbackImage;
  return [
    `<title>${esc(title)}</title>`,
    `<meta name="description" content="${esc(description)}">`,
    `<meta property="og:type" content="website">`,
    `<meta property="og:site_name" content="Zend">`,
    `<meta property="og:url" content="${esc(url)}">`,
    `<meta property="og:title" content="${esc(title)}">`,
    `<meta property="og:description" content="${esc(description)}">`,
    `<meta property="og:image" content="${esc(img)}">`,
    `<meta name="twitter:card" content="summary">`,
    `<meta name="twitter:title" content="${esc(title)}">`,
    `<meta name="twitter:description" content="${esc(description)}">`,
    `<meta name="twitter:image" content="${esc(img)}">`,
  ].join('\n  ');
}

// Headers vercel.json sets on the static page, carried over in case they don't apply to
// function responses.
const KEEP_HEADERS = [
  'content-security-policy',
  'strict-transport-security',
  'x-frame-options',
  'x-content-type-options',
  'referrer-policy',
  'permissions-policy',
];

export default async function handler(request) {
  const url = new URL(request.url);
  const kind = url.searchParams.get('kind');
  const id = url.searchParams.get('id') || '';
  const origin = `${url.protocol}//${url.host}`;

  const indexRes = await fetch(`${origin}/index.html`, { headers: { Accept: 'text/html' } });
  let html = await indexRes.text();
  const headers = new Headers({ 'Content-Type': 'text/html; charset=utf-8' });
  for (const h of KEEP_HEADERS) {
    const v = indexRes.headers.get(h);
    if (v) headers.set(h, v);
  }

  const validId =
    (kind === 'give' && /^0x[0-9a-fA-F]{1,64}$/.test(id)) ||
    (kind === 'ask' && /^zl_[a-z0-9]{4,32}$/.test(id)) ||
    kind === 'cash';
  const preview = indexRes.ok && validId ? await previewFor(kind, id) : null;

  if (preview) {
    const path = kind === 'give' ? `/z/${id}` : kind === 'ask' ? `/a/${id}` : '/cash';
    const tags = headTags({
      ...preview,
      url: `https://app.usezend.app${path}`,
      fallbackImage: `${origin}/icons/Icon-512.png`,
    });
    const block = /<!-- link-preview -->[\s\S]*?<!-- \/link-preview -->/;
    html = block.test(html)
      ? html.replace(block, `<!-- link-preview -->\n  ${tags}\n  <!-- /link-preview -->`)
      : html.replace('</head>', `  ${tags}\n</head>`);
    // Short, so a link that's collected or taken back stops saying "sent you" soon after.
    headers.set('Cache-Control', 'public, s-maxage=60, stale-while-revalidate=300');
  } else {
    headers.set('Cache-Control', 'no-store');
  }

  return new Response(html, { status: indexRes.status, headers });
}
