// Simulate current Mhua5 chapter parsing on real HTML
const fs = require("fs");
const html = fs.readFileSync("F:/softForCode/codex-project/xx-comic/tools/probe-mhua5-detail.html", "utf8");

const CHAPTER_PATTERN = /<li class="j-chapter-item[\s\S]*?<a class="j-chapter-link" href="([^"]+)"[\s\S]*?<\/a>/g;
const MOBILE_PATTERN = /<li class="chapter-item[^"]*"[\s\S]*?<a href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/g;

function clean(s) { return s.replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim(); }
function decode(s) { return s.replace(/&amp;/g, "&").replace(/&quot;/g, '"'); }

// desktop pattern: extract href, then title is text inside <a>
let chapters = [];
let m;
const seen = new Set();
while ((m = CHAPTER_PATTERN.exec(html)) !== null) {
  const href = decode(m[1]);
  if (!seen.add(href)) continue;
  // extract title from the matched <a>...</a> content
  const fullMatch = m[0];
  const aContentMatch = fullMatch.match(/<a class="j-chapter-link"[^>]*>([\s\S]*?)<\/a>/);
  const title = clean(aContentMatch ? aContentMatch[1] : "");
  chapters.push({ href, title });
}
console.log("desktop chapters:", chapters.length);
console.log("first 5:");
chapters.slice(0, 5).forEach((c, i) => console.log("  [" + i + "]", c.href, c.title));
console.log("last 5:");
chapters.slice(-5).forEach((c, i) => console.log("  [-" + (5-i) + "]", c.href, c.title));

// Now simulate normalizeChaptersOldestFirst
function num(t) {
  let mm = /(\d+)/.exec(t);
  return mm ? parseInt(mm[1]) : null;
}
const nums = chapters.map(c => num(c.title)).filter(n => n !== null);
console.log("\nfirst num:", nums[0], "last num:", nums[nums.length - 1]);
console.log("HTML order ascending?", nums[0] < nums[nums.length - 1]);

// Current source: Collections.reverse(chapters)
chapters.reverse();
console.log("\n--- after source reverse (current behavior) ---");
console.log("first 5:");
chapters.slice(0, 5).forEach((c, i) => console.log("  [" + i + "]", c.href, c.title));
console.log("last 5:");
chapters.slice(-5).forEach((c, i) => console.log("  [-" + (5-i) + "]", c.href, c.title));

// Then normalizeChaptersOldestFirst would reverse again if first > last
const reversedNums = chapters.map(c => num(c.title)).filter(n => n !== null);
if (reversedNums[0] > reversedNums[reversedNums.length - 1]) {
  chapters.reverse();
  console.log("\n--- after normalizeChaptersOldestFirst reverse ---");
  console.log("first 5:");
  chapters.slice(0, 5).forEach((c, i) => console.log("  [" + i + "]", c.href, c.title));
}
