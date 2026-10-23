// Slices app/assets/brand/icon.png (the 1024 px «Icon» frame from Figma,
// node 78:2742) into the Windows, macOS and Android launcher icons.
import fs from 'fs';
import { fileURLToPath } from 'url';
import sharp from 'sharp';

const app = fileURLToPath(new URL('../../app', import.meta.url));
const source = `${app}/assets/brand/icon.png`;
// The Figma frame keeps macOS margins (the tile is 832 of 1024 px); Windows
// and Android draw the tile edge to edge.
const tile = sharp(source).extract({ left: 96, top: 96, width: 832, height: 832 });
const png = (img, size) => img.clone().resize(size, size).png().toBuffer();

const mac = `${app}/macos/Runner/Assets.xcassets/AppIcon.appiconset`;
for (const size of [16, 32, 64, 128, 256, 512, 1024]) {
  fs.writeFileSync(`${mac}/app_icon_${size}.png`, await png(sharp(source), size));
}

for (const [q, size] of [['mdpi', 48], ['hdpi', 72], ['xhdpi', 96], ['xxhdpi', 144], ['xxxhdpi', 192]]) {
  fs.writeFileSync(`${app}/android/app/src/main/res/mipmap-${q}/ic_launcher.png`, await png(tile, size));
}

// ICO with PNG entries (Windows Vista and later read them at every size).
const sizes = [16, 24, 32, 48, 64, 128, 256];
const images = await Promise.all(sizes.map(s => png(tile, s)));
const header = Buffer.alloc(6 + 16 * sizes.length);
header.writeUInt16LE(0, 0); header.writeUInt16LE(1, 2); header.writeUInt16LE(sizes.length, 4);
let offset = header.length;
sizes.forEach((s, i) => {
  const e = 6 + 16 * i;
  header.writeUInt8(s % 256, e); header.writeUInt8(s % 256, e + 1);
  header.writeUInt16LE(1, e + 4); header.writeUInt16LE(32, e + 6);
  header.writeUInt32LE(images[i].length, e + 8); header.writeUInt32LE(offset, e + 12);
  offset += images[i].length;
});
fs.writeFileSync(`${app}/windows/runner/resources/app_icon.ico`, Buffer.concat([header, ...images]));
console.log('icons written');
