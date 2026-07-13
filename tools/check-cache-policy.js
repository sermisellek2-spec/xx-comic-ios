const fs = require("fs");

const source = fs.readFileSync(
  "app/src/main/java/com/xxcomic/MainActivity.java",
  "utf8"
);

function trim(files, limit) {
  let total = files.reduce((sum, file) => sum + file.size, 0);
  const removed = [];
  for (const file of [...files].sort((a, b) => a.lastModified - b.lastModified)) {
    if (total <= limit) break;
    total -= file.size;
    removed.push(file.name);
  }
  return { total, removed };
}

function check(name, condition) {
  if (!condition) throw new Error("FAIL " + name);
  console.log("PASS " + name);
}

const result = trim([
  { name: "old", size: 400, lastModified: 1 },
  { name: "middle", size: 400, lastModified: 2 },
  { name: "new", size: 400, lastModified: 3 }
], 1000);

check("oldest cache file is evicted first", result.removed.join(",") === "old");
check("cache is reduced below limit", result.total === 800);
check("image cache limit is 1000 MB", source.includes("IMAGE_CACHE_MAX_BYTES = 1000L * 1024L * 1024L"));
check("disk hits refresh recency", source.includes("cached.setLastModified(System.currentTimeMillis())"));
check("writes enforce cache limit", source.includes("trimImageCache()"));
check("existing cache is trimmed after size restore", source.includes("if (imageCacheBytes > IMAGE_CACHE_MAX_BYTES) trimImageCache();"));
check("manual clear keeps favorite summaries", source.includes("summaries.keySet().retainAll(favoriteIds)"));
check("manual clear keeps favorite details", source.includes("details.keySet().retainAll(favoriteIds)"));
check("manual clear evicts decoded images", source.includes("imageMemoryCache.evictAll()"));
