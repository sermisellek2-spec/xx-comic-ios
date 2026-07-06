const fs = require("fs");
const zlib = require("zlib");

const input = fs.readFileSync(process.argv[2], "utf8");
const match = input.match(/,\s*62\s*,\s*68\s*,\s*'([^']+)'/);
if (!match) throw new Error("packed dictionary not found");

const text = match[1];
const raw = Buffer.from(text, "base64");
console.log("dict chars", text.length, "base64 bytes", raw.length);
console.log("hex head", raw.subarray(0, 32).toString("hex"));
console.log("utf8 head", raw.toString("utf8", 0, 120));

for (const [name, fn] of [
  ["inflate", zlib.inflateSync],
  ["inflateRaw", zlib.inflateRawSync],
  ["gunzip", zlib.gunzipSync],
  ["brotli", zlib.brotliDecompressSync],
]) {
  try {
    const out = fn(raw).toString("utf8");
    console.log(name, out.length, out.slice(0, 500));
  } catch (error) {
    console.log(name, "failed", error.message);
  }
}

const key = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
function getBaseValue(char) {
  return key.indexOf(char);
}

function decompressFromBase64(value) {
  if (!value) return "";
  return decompress(value.length, 32, index => getBaseValue(value.charAt(index)));
}

function decompress(length, resetValue, getNextValue) {
  const dictionary = [0, 1, 2];
  let enlargeIn = 4;
  let dictSize = 4;
  let numBits = 3;
  let entry = "";
  const result = [];
  let bits = 0;
  let maxpower = 4;
  let power = 1;
  const data = { val: getNextValue(0), position: resetValue, index: 1 };

  while (power !== maxpower) {
    const resb = data.val & data.position;
    data.position >>= 1;
    if (data.position === 0) {
      data.position = resetValue;
      data.val = getNextValue(data.index++);
    }
    bits |= (resb > 0 ? 1 : 0) * power;
    power <<= 1;
  }

  let next = bits;
  let c;
  if (next === 0) {
    bits = 0; maxpower = 256; power = 1;
    while (power !== maxpower) {
      const resb = data.val & data.position;
      data.position >>= 1;
      if (data.position === 0) {
        data.position = resetValue;
        data.val = getNextValue(data.index++);
      }
      bits |= (resb > 0 ? 1 : 0) * power;
      power <<= 1;
    }
    c = String.fromCharCode(bits);
  } else if (next === 1) {
    bits = 0; maxpower = 65536; power = 1;
    while (power !== maxpower) {
      const resb = data.val & data.position;
      data.position >>= 1;
      if (data.position === 0) {
        data.position = resetValue;
        data.val = getNextValue(data.index++);
      }
      bits |= (resb > 0 ? 1 : 0) * power;
      power <<= 1;
    }
    c = String.fromCharCode(bits);
  } else {
    return "";
  }

  dictionary[3] = c;
  let w = c;
  result.push(c);

  while (true) {
    if (data.index > length) return "";
    bits = 0;
    maxpower = 1 << numBits;
    power = 1;
    while (power !== maxpower) {
      const resb = data.val & data.position;
      data.position >>= 1;
      if (data.position === 0) {
        data.position = resetValue;
        data.val = getNextValue(data.index++);
      }
      bits |= (resb > 0 ? 1 : 0) * power;
      power <<= 1;
    }
    let code = bits;
    if (code === 0) {
      bits = 0; maxpower = 256; power = 1;
      while (power !== maxpower) {
        const resb = data.val & data.position;
        data.position >>= 1;
        if (data.position === 0) {
          data.position = resetValue;
          data.val = getNextValue(data.index++);
        }
        bits |= (resb > 0 ? 1 : 0) * power;
        power <<= 1;
      }
      dictionary[dictSize++] = String.fromCharCode(bits);
      code = dictSize - 1;
      enlargeIn--;
    } else if (code === 1) {
      bits = 0; maxpower = 65536; power = 1;
      while (power !== maxpower) {
        const resb = data.val & data.position;
        data.position >>= 1;
        if (data.position === 0) {
          data.position = resetValue;
          data.val = getNextValue(data.index++);
        }
        bits |= (resb > 0 ? 1 : 0) * power;
        power <<= 1;
      }
      dictionary[dictSize++] = String.fromCharCode(bits);
      code = dictSize - 1;
      enlargeIn--;
    } else if (code === 2) {
      return result.join("");
    }
    if (enlargeIn === 0) {
      enlargeIn = 1 << numBits;
      numBits++;
    }
    if (dictionary[code]) entry = dictionary[code];
    else if (code === dictSize) entry = w + w.charAt(0);
    else return "";
    result.push(entry);
    dictionary[dictSize++] = w + entry.charAt(0);
    enlargeIn--;
    w = entry;
    if (enlargeIn === 0) {
      enlargeIn = 1 << numBits;
      numBits++;
    }
  }
}

const lz = decompressFromBase64(text);
console.log("lz", lz.length, lz.slice(0, 1000));
console.log("lz parts", lz.split("|").length);

function base62(c, a) {
  if (c < a) return c > 35 ? String.fromCharCode(c + 29) : c.toString(36);
  return base62(Math.floor(c / a), a) + base62(c % a, a);
}

const pack = input.match(/\(\s*'((?:\\.|[^'\\])*)'\s*,\s*(\d+)\s*,\s*(\d+)/);
if (pack) {
  let unpacked = pack[1];
  const radix = Number(pack[2]);
  const count = Number(pack[3]);
  const dict = lz.split("|");
  const values = new Map();
  for (let i = Math.max(count, dict.length) - 1; i >= 0; i--) {
    if (dict[i]) values.set(base62(i, radix), dict[i]);
  }
  unpacked = unpacked.replace(/[0-9A-Za-z]+/g, token => values.get(token) || token);
  console.log("unpacked", unpacked.slice(0, 1600));
}
