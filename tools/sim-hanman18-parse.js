// Mirrors Hanman18ComicSource.chapter() image extraction for offline verification.
// Reader pages encode image URLs as base64 in `var slides_p_path = [ ... ]`,
// then JS injects <img src='atob(token)'> into #chapter_boxImages at load.
const FIXTURE = `<script>var slides_page;var slides_p_path=["aHR0cHM6Ly9hem1pbnYyLmhhbm1hbjE4LmNvbS91cGxvYWRzL2NoYXB0ZXJzLzc2MDM3LzAxLmpwZw==","aHR0cHM6Ly9hem1pbnYyLmhhbm1hbjE4LmNvbS91cGxvYWRzL2NoYXB0ZXJzLzc2MDM3LzAyLmpwZw==","aHR0cHM6Ly9hem1pbnYyLmhhbm1hbjE4LmNvbS91cGxvYWRzL2NoYXB0ZXJzLzc2MDM3LzAzLmpwZw==","aHR0cHM6Ly9hem1pbnYyLmhhbm1hbjE4LmNvbS91cGxvYWRzL2NoYXB0ZXJzLzc2MDM3LzA0LmpwZw==","aHR0cHM6Ly9hem1pbnYyLmhhbm1hbjE4LmNvbS91cGxvYWRzL2NoYXB0ZXJzLzc2MDM3LzA1LmpwZw==",];$(document).ready(function(){var i=0;setInterval(function(){atob(slides_p_path[i]);i++;},100);});</script>`;

function extractSlideImages(html) {
  const images = [];
  const seen = new Set();
  const arr = /slides_p_path\s*=\s*\[([\s\S]*?)\]/.exec(html);
  if (!arr) return images;
  const body = arr[1];
  const re = /["']([A-Za-z0-9+/=]+)["']/g;
  let m;
  while ((m = re.exec(body)) !== null) {
    const b64 = m[1];
    if (b64.length < 8) continue;
    try {
      const url = Buffer.from(b64, 'base64').toString('utf8');
      if (url.startsWith('http') && seen.add(url)) images.push(url);
    } catch (e) {}
  }
  return images;
}

const imgs = extractSlideImages(FIXTURE);
console.log('count:', imgs.length);
imgs.forEach(u => console.log('  ', u));
console.log('first==expected:', imgs[0] === 'https://azminv2.hanman18.com/uploads/chapters/76037/01.jpg');
