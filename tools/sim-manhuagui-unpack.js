// Mirrors ManhuaguiComicSource.extractImgData + buildImageUrls for offline verification.
// Usage: node tools/sim-manhuagui-unpack.js <file-containing-the-packed-script>
// Reads the raw <script> (the one with function(p,a,c,k,e,d){...}('payload',A,C,'dict'.split('|'),0,{})),
// decodes the dean-edwards packer, prints the SMH.imgData({...}) config + first image URL.
const fs = require('fs');
const input = fs.readFileSync(process.argv[2] || 0, 'utf8');

function base62(c, a) {
    if (c < a) return (c > 35) ? String.fromCharCode(c + 29) : c.toString(36);
    return base62(Math.floor(c / a), a) + base62(c % a, a);
}
function unescapeJs(s) {
    let out = '';
    for (let i = 0; i < s.length; i++) {
        if (s[i] === '\\' && i + 1 < s.length) {
            const n = s[i + 1];
            if (n === "'") { out += "'"; i++; }
            else if (n === '"') { out += '"'; i++; }
            else if (n === '\\') { out += '\\'; i++; }
            else if (n === '/') { out += '/'; i++; }
            else if (n === 'n') { out += '\n'; i++; }
            else if (n === 'r') { out += '\r'; i++; }
            else if (n === 't') { out += '\t'; i++; }
            else if (n === 'b') { out += '\b'; i++; }
            else if (n === 'f') { out += '\f'; i++; }
            else if (n === 'x' && i + 3 < s.length) { out += String.fromCharCode(parseInt(s.slice(i + 2, i + 4), 16)); i += 3; }
            else if (n === 'u' && i + 5 < s.length) { out += String.fromCharCode(parseInt(s.slice(i + 2, i + 6), 16)); i += 5; }
            else { out += n; i++; }
        } else out += s[i];
    }
    return out;
}
function extractImgData(html) {
    const m = html.match(/\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'((?:[^'\\]|\\.)*)'\s*(?:\.\s*split|\[[^\]]*\])\s*\(\s*'([^']*)'\s*\)/);
    if (!m) return null;
    const payload = unescapeJs(m[1]);
    const a = parseInt(m[2], 10), c = parseInt(m[3], 10);
    const dict = unescapeJs(m[4]).split(unescapeJs(m[5]));
    let result = payload;
    for (let i = c - 1; i >= 0; i--) {
        if (dict[i]) {
            const token = base62(i, a);
            result = result.replace(new RegExp('\\b' + token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b', 'g'), dict[i]);
        }
    }
    const s = result.indexOf('{'), e = result.lastIndexOf('}');
    return (s >= 0 && e > s) ? result.slice(s, e + 1) : null;
}

const config = extractImgData(input);
if (!config) { console.log('NO PACKER MATCHED'); process.exit(1); }
console.log('CONFIG:', config);
try {
    const root = JSON.parse(config);
    console.log('bid:', root.bid, '| cid:', root.cid, '| len:', root.len, '| files:', root.files && root.files.length);
    console.log('path:', root.path);
    console.log('sl:', JSON.stringify(root.sl));
    if (root.files && root.files.length) {
        const enc = root.path.split('/').map(s => s ? encodeURIComponent(s) : '').join('/');
        console.log('first image:', 'https://eu2.hamreus.com' + enc + root.files[0] + '?e=' + root.sl.e + '&m=' + root.sl.m);
    }
} catch (e) { console.log('JSON parse failed:', e.message); }
