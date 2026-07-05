// Simulate the current Aikan chapter parsing logic on real HTML
const fs = require("fs");

const html = fs.readFileSync("F:/softForCode/codex-project/xx-comic/tools/probe-aikan-detail.html", "utf8");

// === simulate chapterDirectoryBlock (PROPOSED FIX) ===
function chapterDirectoryBlock(html) {
  let title = html.indexOf("章节目录");
  if (title < 0) return html || "";
  // start from "章节目录" position so the first <a> tag is included
  let end = html.indexOf("but-vip", title);
  if (end < 0) end = html.indexOf("section-title", title + 1);
  if (end < 0) end = html.length;
  return html.substring(title, end);
}

// === simulate CHAPTER_PATTERN ===
// <a href="([^"]*?/chook/\d+)"[^>]*class="comics-chapters__item[^"]*"[^>]*?[\s\S]*?<span[^>]*>([\s\S]*?)</span>
const CHAPTER_PATTERN = /<a href="([^"]*?\/chook\/\d+)"[^>]*class="comics-chapters__item[^"]*"[^>]*?[\s\S]*?<span[^>]*>([\s\S]*?)<\/span>/g;

function clean(s) { return s.replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim(); }
function decode(s) { return s.replace(/&amp;/g, "&").replace(/&quot;/g, '"'); }
function isNoticeChapter(t) { return t.includes("公告") || t.includes("查看更多") || t.includes("最新"); }
function rawChapterId(href) {
  let d = decode(href);
  let q = d.indexOf("?");
  if (q >= 0) d = d.substring(0, q);
  let s = d.lastIndexOf("/");
  return s >= 0 ? d.substring(s + 1).trim() : d.trim();
}

const block = chapterDirectoryBlock(html);
console.log("block length:", block.length, "starts at:", html.indexOf(block));

let matches = [];
let m;
while ((m = CHAPTER_PATTERN.exec(block)) !== null) {
  matches.push({ href: decode(m[1]), title: clean(m[2]) });
}
console.log("total pattern matches in block:", matches.length);

// dedup like current code
const seen = new Set();
const seenTitles = new Set();
const chapters = [];
for (const { href, title } of matches) {
  if (!title || isNoticeChapter(title) || !seen.add(href) || !seenTitles.add(title)) continue;
  chapters.push({ href, title, id: rawChapterId(href) });
}
console.log("after dedup:", chapters.length);

// Check for chapter 001
const ch001 = matches.find(m => m.href.includes("116040"));
console.log("\nchapter 001 match:", ch001 ? { href: ch001.href, title: ch001.title } : "NOT MATCHED");

// Show very first 3 raw matches
console.log("\nfirst 3 raw matches:");
matches.slice(0, 3).forEach((c, i) => console.log("  [" + i + "]", c.href, c.title));

console.log("\nfirst 5:");
chapters.slice(0, 5).forEach((c, i) => console.log("  [" + i + "]", c.id, c.title));
console.log("\nlast 5:");
chapters.slice(-5).forEach((c, i) => console.log("  [-" + (5-i) + "]", c.id, c.title));

// Check if directory is ascending or descending by extracting numbers
function num(t) {
  let mm = /(\d+)/.exec(t);
  return mm ? parseInt(mm[1]) : null;
}
const nums = chapters.map(c => num(c.title)).filter(n => n !== null);
console.log("\nfirst chapter num:", nums[0], "last chapter num:", nums[nums.length - 1]);
console.log("ascending?", nums[0] < nums[nums.length - 1]);
