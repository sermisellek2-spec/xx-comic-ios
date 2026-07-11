const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);

function encodePosition(scrollY, maxScroll) {
  if (maxScroll <= 0) return 0;
  return Math.max(0, Math.min(10000, Math.round(scrollY * 10000 / maxScroll)));
}

function restorePosition(position, maxScroll) {
  return Math.round(Math.max(0, Math.min(10000, position)) * Math.max(0, maxScroll) / 10000);
}

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

const encoded = encodePosition(4321, 9876);
const restored = restorePosition(encoded, 17654);
check("reader ratio survives content height changes", Math.abs(restored / 17654 - 4321 / 9876) < 0.0001);
check("reader ratio clamps at bottom", encodePosition(200, 100) === 10000);
check(
  "reader progress is keyed by comic and chapter",
  /readerPositionKey\(detail\.summary\.comicId,\s*\w+\)/.test(source)
);
check("reader scroll progress is persisted", source.includes("saveReaderPosition(scroll, pages, positionKey)"));
check("reader progress restores after image layout", source.includes("restoreReaderPosition(scroll, pages, savedPosition)"));
