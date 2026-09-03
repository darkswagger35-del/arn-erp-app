const SUPABASE_URL = 'https://ewcczprgzghpttrwsamm.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_cw6q5TJG_vo_dyL4WUk-Bw_-4zFU2Bn';
const MOTUS_REFERER = 'https://motus-app-three.vercel.app/';

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');

  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ message: 'Method not allowed.' });
  }

  const authorization = req.headers.authorization || '';
  if (!authorization.toLowerCase().startsWith('bearer ')) {
    return res.status(401).json({ message: 'Authentication required.' });
  }

  try {
    const userResponse = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: {
        Authorization: authorization,
        apikey: SUPABASE_PUBLISHABLE_KEY,
      },
    });
    if (!userResponse.ok) {
      return res.status(401).json({ message: 'MOTUS oturumu doğrulanamadı.' });
    }
  } catch (_) {
    return res.status(503).json({ message: 'MOTUS oturum servisine ulaşılamadı.' });
  }

  const apiKey = process.env.YANDEX_GEOCODER_API_KEY || '';
  if (!apiKey.trim()) {
    return res.status(503).json({
      message: 'Yandex Geocoder API anahtarı Vercel ortamında tanımlı değil.',
    });
  }

  const body = typeof req.body === 'string'
    ? (() => { try { return JSON.parse(req.body); } catch (_) { return {}; } })()
    : (req.body || {});
  const query = String(body.query || '').trim();
  if (!query || query.length > 500) {
    return res.status(400).json({ message: 'Geçerli bir adres gerekli.' });
  }

  const params = new URLSearchParams({
    apikey: apiKey.trim(),
    geocode: query,
    lang: 'tr_TR',
    format: 'json',
    results: '10',
  });

  try {
    const response = await fetch(`https://geocode-maps.yandex.ru/v1/?${params.toString()}`, {
      headers: {
        Accept: 'application/json',
        Referer: MOTUS_REFERER,
      },
    });
    const text = await response.text();
    let payload;
    try {
      payload = JSON.parse(text);
    } catch (_) {
      payload = { message: text || 'Yandex geçersiz yanıt verdi.' };
    }
    if (!response.ok) {
      return res.status(response.status).json({
        message: payload?.message || `Yandex Geocoder ${response.status}`,
      });
    }
    return res.status(200).json(payload);
  } catch (_) {
    return res.status(503).json({ message: 'Yandex Geocoder servisine ulaşılamadı.' });
  }
};
