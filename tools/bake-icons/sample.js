// Runs in the page. Mounts one icon, samples every frame of start and stop.
window.bake = async (name) => {
  const host = document.getElementById('root'); host.innerHTML = '';
  const ref = { current: null };
  const root = createRoot(host);
  root.render(React.createElement(ICONS[name], { ref, size: 96 }));
  await new Promise(r => setTimeout(r, 300));
  const svg = host.querySelector('svg');
  const vb = svg.viewBox.baseVal;
  const k = vb.width / svg.width.baseVal.value;
  const shapes = [...svg.querySelectorAll('path,circle,ellipse,line,rect,polyline,polygon')];
  const n = v => +(+v).toFixed(3);
  const geom = el => {
    const a = x => +el.getAttribute(x) || 0;
    switch (el.tagName) {
      case 'path': return el.getAttribute('d');
      case 'circle': case 'ellipse': { const cx = a('cx'), cy = a('cy'), rx = a('r') || a('rx'), ry = a('r') || a('ry');
        return `M${cx - rx} ${cy}a${rx} ${ry} 0 1 0 ${2 * rx} 0a${rx} ${ry} 0 1 0 ${-2 * rx} 0`; }
      case 'line': return `M${a('x1')} ${a('y1')}L${a('x2')} ${a('y2')}`;
      case 'rect': { const x = a('x'), y = a('y'), w = a('width'), h = a('height'), r = Math.min(a('rx') || a('ry'), w / 2, h / 2);
        return r ? `M${x + r} ${y}H${x + w - r}A${r} ${r} 0 0 1 ${x + w} ${y + r}V${y + h - r}A${r} ${r} 0 0 1 ${x + w - r} ${y + h}H${x + r}A${r} ${r} 0 0 1 ${x} ${y + h - r}V${y + r}A${r} ${r} 0 0 1 ${x + r} ${y}Z`
                 : `M${x} ${y}H${x + w}V${y + h}H${x}Z`; }
      default: return 'M' + el.getAttribute('points').trim() + (el.tagName === 'polygon' ? 'Z' : '');
    }
  };
  const frame = () => shapes.map(el => {
    const m = el.getScreenCTM(), h = host.getBoundingClientRect();
    let o = 1; for (let e = el; e && e !== svg.parentNode; e = e.parentNode) o *= +getComputedStyle(e).opacity;
    const cs = getComputedStyle(el);
    return {
      d: geom(el),
      m: [m.a * k, m.b * k, m.c * k, m.d * k, (m.e - h.left) * k + vb.x, (m.f - h.top) * k + vb.y].map(n),
      o: n(o),
      fill: cs.fill, stroke: cs.stroke, sw: n(parseFloat(cs.strokeWidth)),
      pl: el.getAttribute('pathLength'), da: cs.strokeDasharray, dof: cs.strokeDashoffset,
      vis: cs.visibility, disp: cs.display,
    };
  });
  const run = async (max) => {
    const out = []; const t0 = performance.now(); let last = '', still = 0;
    while (true) {
      await new Promise(r => requestAnimationFrame(r));
      const t = performance.now() - t0, f = frame(), s = JSON.stringify(f);
      out.push({ t: n(t / 1000), f });
      still = s === last ? still + 1 : 0; last = s;
      if (t > max * 1000 || (t > 300 && still > 12)) break;
    }
    return out;
  };
  const rest = frame();
  const api = ref.current;
  if (!api?.startAnimation) return { vb: [vb.x, vb.y, vb.width, vb.height], rest, start: [], stop: [], static: true };
  api.startAnimation();
  const start = await run(4);
  api.stopAnimation?.();
  const stop = await run(1.5);
  root.unmount();
  return { vb: [vb.x, vb.y, vb.width, vb.height], rest, start, stop };
};
