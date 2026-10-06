// CORS-прокси для веб-версии: сайты колледжей (кроме GitHub Pages) не отдают
// Access-Control-Allow-Origin, и браузер не даёт прочитать их HTML напрямую.
// GET /api/proxy?url=https://bbb.zabgc.ru/cg.htm
// Отдаёт только HTML/текст до 3 МБ — чтобы это не стало открытым прокси для всего подряд.

const MAX_BYTES = 3 * 1024 * 1024;
const PRIVATE_HOST =
  /^(localhost|.*\.local|.*\.internal|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|0\.|\[)/i;

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "GET") return res.status(405).end();

  try {
    let target = String(req.query.url || "");
    let upstream;
    // Редиректы руками: иначе внешний сайт мог бы перенаправить прокси на внутренний адрес.
    for (let hop = 0; hop < 4; hop++) {
      const url = new URL(target);
      if (!/^https?:$/.test(url.protocol) || PRIVATE_HOST.test(url.hostname)) {
        return res.status(400).send("forbidden url");
      }
      upstream = await fetch(url, {
        headers: { "User-Agent": "Mozilla/5.0 (Raspisanie web)" },
        redirect: "manual",
        signal: AbortSignal.timeout(12000),
      });
      const location = upstream.headers.get("location");
      if (upstream.status < 300 || upstream.status >= 400 || !location) break;
      target = new URL(location, url).href;
    }
    const type = upstream.headers.get("content-type") || "text/html";
    if (!/^text\/|html|xml/i.test(type)) return res.status(415).send("not html");
    const body = Buffer.from(await upstream.arrayBuffer());
    if (body.length > MAX_BYTES) return res.status(413).send("too large");

    res.setHeader("Content-Type", type);
    // Расписание меняется редко, а 50 студентов на одной группе — частый случай.
    res.setHeader("Cache-Control", "public, s-maxage=120, stale-while-revalidate=600");
    return res.status(upstream.status).send(body);
  } catch (e) {
    return res.status(502).send(`upstream error: ${e.message}`);
  }
};
