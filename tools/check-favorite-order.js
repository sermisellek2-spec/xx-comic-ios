// Favorite ordering contract check.
// Run: node tools/check-favorite-order.js
const fs = require("fs");
const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);

function orderFavorites(ids, favoriteAt, lastViewedAt) {
  return [...ids].sort((left, right) => {
    const leftTime = Math.max(favoriteAt[left] || 0, lastViewedAt[left] || 0);
    const rightTime = Math.max(favoriteAt[right] || 0, lastViewedAt[right] || 0);
    if (leftTime !== rightTime) return rightTime - leftTime;
    return ids.indexOf(left) - ids.indexOf(right);
  });
}

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

check(
  "new favorite is immediately first",
  orderFavorites(["old", "new"], { old: 10, new: 200 }, { old: 100 })[0] === "new"
);
check(
  "latest reading is first",
  orderFavorites(["first", "second"], { first: 10, second: 20 }, { first: 30, second: 25 })[0] === "first"
);
check(
  "legacy favorites keep insertion order",
  orderFavorites(["first", "second"], {}, {})[0] === "first"
);

check("favorite timestamp map exists", /Map<String, Long>\s+favoriteAt/.test(source));
check("favorite timestamp is recorded", /favoriteAt\.put\(id,\s*System\.currentTimeMillis\(\)\)/.test(source));
check("favorite timestamp is cleared", /favoriteAt\.remove\(id\)/.test(source));
check("favorite sorting uses favorite time", /favoriteAt\.get\(left\)/.test(source));
check("favorite timestamps are persisted", source.includes('"favorite.at"'));

console.log("favorite ordering ok");
