// Writes entry.jsx: every ItsHover component from map.json, exposed to the sampler page.
import fs from 'fs';
const files = [...new Set(Object.values(JSON.parse(fs.readFileSync('map.json'))))];
fs.writeFileSync('entry.jsx', [
  'import React from "react"; import { createRoot } from "react-dom/client";',
  ...files.map((f, i) => `import C${i} from "./icons/${f}";`),
  `window.ICONS = {${files.map((f, i) => `"${f}": C${i}`).join(', ')}}; window.React = React; window.createRoot = createRoot;`,
].join('\n'));
