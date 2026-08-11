const fs = require("fs");

const expected = {
  mdpi: [48, 108],
  hdpi: [72, 162],
  xhdpi: [96, 216],
  xxhdpi: [144, 324],
  xxxhdpi: [192, 432],
};

function dimensions(path) {
  const png = fs.readFileSync(path);
  if (png.toString("hex", 0, 8) !== "89504e470d0a1a0a") {
    throw new Error(`${path}: not PNG`);
  }
  return [png.readUInt32BE(16), png.readUInt32BE(20)];
}

for (const [density, [legacy, adaptive]] of Object.entries(expected)) {
  const launcher = `app/src/main/res/mipmap-${density}/ic_launcher.png`;
  const foreground = `app/src/main/res/drawable-${density}/ic_launcher_foreground.png`;
  if (dimensions(launcher).join("x") !== `${legacy}x${legacy}`) {
    throw new Error(`${launcher}: wrong size`);
  }
  if (dimensions(foreground).join("x") !== `${adaptive}x${adaptive}`) {
    throw new Error(`${foreground}: wrong size`);
  }
}

const adaptive = fs.readFileSync(
  "app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml",
  "utf8",
);
if (!adaptive.includes('@drawable/ic_launcher_foreground')) {
  throw new Error("adaptive foreground reference missing");
}

const gradle = fs.readFileSync("app/build.gradle", "utf8");
if (!/release\s*\{[\s\S]*signingConfig signingConfigs\.debug/.test(gradle)) {
  throw new Error("release debug signing missing");
}

console.log("launcher icon resources ok");
