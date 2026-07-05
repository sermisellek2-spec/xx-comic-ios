// Mirrors Hanman18ComicSource.parsePopular() for offline verification.
// Home page has <h5>受欢迎的</h5> section with story_item cards (cover anchor has title attr).
// Note the commented-out story_chapter <span>114</span> — must not be picked as the time.
const FIXTURE = '<div class="mg_update"><div class="container"><div class="mg_update-content">'
  + '<div class="section_title"><h5>受欢迎的</h5></div>'
  + '<div class="mg_update-owl owl-carousel owl-theme ">'
  + '<div class="story_item"><div class="story_images"><a href="https://hanman18.com/manhwa/mimijiaohua" title="秘密教學"><img src="https://azminv2.hanman18.com/uploads/manga/mimijiaohua/cover/cover_thumb_2.webp" alt="" class="img-responsive"></a></div>'
  + '<div class="story_info"><div class="story_name"><a href="https://hanman18.com/manhwa/mimijiaohua">秘密教學</a></div>'
  + '<div class="story_other"><!-- <div class="story_chapter"><a href="#">Chapter <span>114</span></a></div> --><div class="story_time"><i class="ti-timer"></i> <span>1 week ago</span></div></div></div></div>'
  + '<div class="story_item"><div class="story_images"><a href="https://hanman18.com/manhwa/shechanhuazi" title="社團學姊"><img src="https://azminv2.hanman18.com/uploads/manga/shechanhuazi/cover/cover_thumb_2.webp" alt="" class="img-responsive"></a></div>'
  + '<div class="story_info"><div class="story_name"><a href="https://hanman18.com/manhwa/shechanhuazi">社團學姊</a></div>'
  + '<div class="story_other"><!-- <div class="story_chapter"><a href="#">Chapter <span>114</span></a></div> --><div class="story_time"><i class="ti-timer"></i> <span>1 year ago</span></div></div></div></div>'
  + '<div class="story_item"><div class="story_images"><a href="https://hanman18.com/manhwa/738" title="復仇母女丼"><img src="https://azminv2.hanman18.com/uploads/manga/738/cover/cover_thumb_2.webp" alt="" class="img-responsive"></a></div>'
  + '<div class="story_info"><div class="story_name"><a href="https://hanman18.com/manhwa/738">復仇母女丼</a></div>'
  + '<div class="story_other"><!-- <div class="story_chapter"><a href="#">Chapter <span>114</span></a></div> --><div class="story_time"><i class="ti-timer"></i> <span>3 months ago</span></div></div></div></div>'
  + '</div></div></div></div>'
  + '<div class="mg_update"><div class="section_title"><h5>最新</h5></div><div class="mg_update-owl"><div class="story_item"><div class="story_images"><a href="https://hanman18.com/manhwa/other" title="其他"><img src="https://azminv2.hanman18.com/uploads/manga/other/cover/cover_thumb_2.webp"></a></div><div class="story_other"><div class="story_time"><span>2 days ago</span></div></div></div></div></div>';

function parsePopular(html) {
  const results = [];
  const seen = new Set();
  let body = html.replace(/<!--[\s\S]*?-->/g, '');
  const sec = /<h5[^>]*>受欢迎的<\/h5>([\s\S]*?)(?=<h5[^>]*>|$)/.exec(body);
  body = sec ? sec[1] : '';
  const itemRe = /<div class="story_item"[\s\S]*?(?=<div class="story_item"|$)/g;
  let m;
  while ((m = itemRe.exec(body)) !== null) {
    const block = m[0];
    const a = /<a[^>]+href="([^"]*\/manhwa\/[^"]+)"[^>]*title="([^"]*)"/.exec(block);
    if (!a) continue;
    const slug = a[1].match(/\/manhwa\/([^/?#]+)/)[1];
    if (!seen.add(slug)) continue;
    const img = /<img\s+src="([^"]+)"/.exec(block);
    const time = /<span>([^<]+)<\/span>/.exec(block);
    results.push({slug: slug, title: a[2], cover: img ? img[1] : '', time: time ? time[1].trim() : ''});
  }
  return results;
}

const r = parsePopular(FIXTURE);
console.log('count:', r.length, '(expect 3, not 4 — 最新 section excluded)');
r.forEach(x => console.log('  ', x.slug, '|', x.title, '|', x.time, '|', x.cover.slice(-30)));
console.log('first slug ok:', r[0] && r[0].slug === 'mimijiaohua');
console.log('numeric slug ok:', r[2] && r[2].slug === '738');
console.log('time not 114:', r[0] && r[0].time === '1 week ago');
