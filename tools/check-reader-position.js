const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);

function encodePosition(firstVisible, firstTop, firstHeight, count, lastVisible, lastBottom, viewportBottom) {
  if (count <= 0) return 0;
  if (lastVisible === count - 1 && lastBottom <= viewportBottom) return 10000;
  const offset = firstHeight > 0 ? Math.max(0, Math.min(1, -firstTop / firstHeight)) : 0;
  return Math.max(0, Math.min(10000, Math.round((firstVisible + offset) * 10000 / count)));
}

function restorePosition(position, count, rowHeight) {
  const row = Math.max(0, Math.min(count - 1, Math.max(0, Math.min(10000, position)) * count / 10000));
  return { index: Math.floor(row), top: -Math.round((row - Math.floor(row)) * rowHeight) };
}

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

const encoded = encodePosition(12, -300, 1200, 40);
const restored = restorePosition(encoded, 40, 800);
check("reader row ratio round trips", restored.index === 12 && Math.abs(restored.top + 200) <= 2);
check("reader ratio clamps at bottom", encodePosition(40, 0, 100, 40) === 10000);
check("reader bottom alignment encodes exactly", encodePosition(36, 0, 100, 40, 39, 800, 800) === 10000);
check(
  "reader progress is keyed by comic and chapter",
  /readerPositionKey\(detail\.summary\.comicId,\s*\w+\)/.test(source)
);
check("reader position reads the first visible row", /getFirstVisiblePosition\(\)/.test(source));
check("reader position reads first child offset", /getChildAt\(0\)[\s\S]*?getTop\(\)[\s\S]*?getHeight\(\)/.test(source));
check("reader position uses adapter count", /list\.getCount\(\)/.test(source));
check("reader detects the last visible row", /getLastVisiblePosition\(\)/.test(source));
check("reader detects bottom-aligned last child", /lastChild\.getBottom\(\)[\s\S]*?list\.getHeight\(\)/.test(source));
check("reader saves exact chapter bottom", /position\s*=\s*READER_POSITION_SCALE/.test(source));
check("reader scroll progress is persisted", source.includes("saveReaderPosition(list, positionKey)"));
check("reader progress restores by row and offset", /setSelectionFromTop\(index, top\)/.test(source));
check("reader bottom restore has a dedicated branch", /savedPosition\s*==\s*READER_POSITION_SCALE/.test(source));
check("reader bottom restore waits for the last child", /list\.post\(\(\)\s*->\s*alignReaderBottom\(list\)\)/.test(source));
check("reader bottom restore aligns measured row to viewport", /int last\s*=\s*list\.getCount\(\)\s*-\s*1[\s\S]*?int childHeight\s*=\s*lastChild\.getHeight\(\)[\s\S]*?int listHeight\s*=\s*Math\.max\([\s\S]*?list\.getHeight\(\)[\s\S]*?setSelectionFromTop\(last, listHeight - childHeight\)/.test(source));
check("reader scroll saves through ListView listener", /setOnScrollListener\(new AbsListView\.OnScrollListener\(\)/.test(source));
check("reader persistence remains debounced", /READER_POSITION_SAVE_DELAY_MS\s*=\s*250L/.test(source));
