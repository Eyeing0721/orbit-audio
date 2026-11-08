const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

const menu = $('#mobile-nav');
const menuToggle = $('.menu-toggle');
menuToggle?.addEventListener('click', () => {
  const expanded = menuToggle.getAttribute('aria-expanded') === 'true';
  menuToggle.setAttribute('aria-expanded', String(!expanded));
  menuToggle.setAttribute('aria-label', expanded ? '打开导航' : '关闭导航');
  menu.hidden = expanded;
});
$$('a', menu).forEach(link => link.addEventListener('click', () => {
  menu.hidden = true;
  menuToggle.setAttribute('aria-expanded', 'false');
  menuToggle.setAttribute('aria-label', '打开导航');
}));
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && !menu.hidden) {
    menu.hidden = true;
    menuToggle.setAttribute('aria-expanded', 'false');
    menuToggle.setAttribute('aria-label', '打开导航');
    menuToggle.focus();
  }
});

const previews = {
  spatial: { image: 'workspace.png', alt: 'ORBIT 深灰 M3 工作台：三维声场、声音对象属性与底部关键帧编辑器', description: '在三维声场中摆放对象，在底部时间轴编排位置与效果动画。' },
  nodes: { image: 'nodes.png', alt: 'ORBIT 对象节点编辑器：并联混响、增益和混合节点的实际连线', description: '把处理链路画出来。连接、分支、旁路，也可以切换到主输出节点。' },
  curves: { image: 'curves.png', alt: 'ORBIT 贝塞尔动画曲线编辑器与三维声音场景', description: '用关键帧与贝塞尔手柄控制节奏，让距离和效果自然变化。' },
  spectrum: { image: 'spectrum.png', alt: 'ORBIT 手动计算的源音频 STFT 频谱热图', description: '观察源音频或剪辑／节点处理后的频谱，不是实时总线分析。' }
};
const previewTabs = $$('[data-preview]');
function selectPreview(tab) {
  const key = tab.dataset.preview;
  const preview = previews[key];
  if (!preview) return;
  for (const item of previewTabs) {
    const selected = item === tab;
    item.setAttribute('aria-selected', String(selected));
    item.tabIndex = selected ? 0 : -1;
  }
  $('#workspace-preview').src = '/assets/' + preview.image;
  $('#workspace-preview').alt = preview.alt;
  $('#preview-description').textContent = preview.description;
  $('#full-preview').href = '/assets/' + preview.image;
  $('#preview-panel').setAttribute('aria-labelledby', tab.id);
}
previewTabs.forEach((tab, index) => {
  tab.addEventListener('click', () => selectPreview(tab));
  tab.addEventListener('keydown', event => {
    let next = index;
    if (event.key === 'ArrowRight') next = (index + 1) % previewTabs.length;
    else if (event.key === 'ArrowLeft') next = (index - 1 + previewTabs.length) % previewTabs.length;
    else if (event.key === 'Home') next = 0;
    else if (event.key === 'End') next = previewTabs.length - 1;
    else return;
    event.preventDefault();
    selectPreview(previewTabs[next]);
    previewTabs[next].focus();
  });
});

const scene = $('#spatial-scene');
const positions = {
  voice: { x: 280, y: 115, label: '人声' },
  bed: { x: 132, y: 307, label: '伴奏' },
  rain: { x: 422, y: 326, label: '雨幕' }
};
const initial = structuredClone(positions);
let dragging = null;
let arrival = false;
let spread = false;
function moveSource(key, x, y) {
  const position = positions[key];
  position.x = Math.max(80, Math.min(475, x));
  position.y = Math.max(92, Math.min(353, y));
  const group = $('#source-' + key);
  group.setAttribute('transform', 'translate(' + position.x + ' ' + position.y + ')');
  const worldX = (position.x - 280) / 38;
  const worldY = (285 - position.y) / 26;
  group.setAttribute('aria-label', position.label + '对象，X ' + worldX.toFixed(1) + ' 米，Y ' + worldY.toFixed(1) + ' 米；方向键移动');
  $('#coordinates').textContent = 'X ' + worldX.toFixed(1) + ' / Y ' + (worldY >= 0 ? '+' : '') + worldY.toFixed(1) + ' m';
}
function scenePoint(event) {
  return new DOMPoint(event.clientX, event.clientY).matrixTransform(scene.getScreenCTM().inverse());
}
$$('[data-source]', scene).forEach(group => {
  const key = group.dataset.source;
  group.addEventListener('pointerdown', event => {
    if (event.button !== 0) return;
    const point = scenePoint(event);
    dragging = { key, offsetX: point.x - positions[key].x, offsetY: point.y - positions[key].y, pointer: event.pointerId };
    group.setPointerCapture(event.pointerId);
    group.focus({ preventScroll: true });
    event.preventDefault();
  });
  group.addEventListener('pointermove', event => {
    if (!dragging || dragging.key !== key || dragging.pointer !== event.pointerId) return;
    const point = scenePoint(event);
    moveSource(key, point.x - dragging.offsetX, point.y - dragging.offsetY);
  });
  group.addEventListener('pointerup', () => { dragging = null; });
  group.addEventListener('pointercancel', () => { dragging = null; });
  group.addEventListener('lostpointercapture', () => { dragging = null; });
  group.addEventListener('keydown', event => {
    const step = event.shiftKey ? 20 : 6;
    const { x, y } = positions[key];
    if (event.key === 'ArrowLeft') moveSource(key, x - step, y);
    else if (event.key === 'ArrowRight') moveSource(key, x + step, y);
    else if (event.key === 'ArrowUp') moveSource(key, x, y - step);
    else if (event.key === 'ArrowDown') moveSource(key, x, y + step);
    else if (event.key === 'Home') moveSource(key, initial[key].x, initial[key].y);
    else return;
    event.preventDefault();
  });
});
$('#arrival-button').addEventListener('click', () => {
  arrival = !arrival;
  moveSource('voice', 280, arrival ? 254 : 115);
  $('#arrival-button').setAttribute('aria-pressed', String(arrival));
});
$('#spread-button').addEventListener('click', () => {
  spread = !spread;
  moveSource('bed', spread ? 90 : 132, spread ? 342 : 307);
  moveSource('rain', spread ? 469 : 422, spread ? 342 : 326);
  $('#spread-button').setAttribute('aria-pressed', String(spread));
});
$('#reset-scene').addEventListener('click', () => {
  for (const key of Object.keys(initial)) moveSource(key, initial[key].x, initial[key].y);
  arrival = false;
  spread = false;
  $('#arrival-button').setAttribute('aria-pressed', 'false');
  $('#spread-button').setAttribute('aria-pressed', 'false');
  $('#coordinates').textContent = 'Y +6.5 m';
});

let toastTimer;
const nodeVisual = $('.node-visual');
function drawNodeWires() {
  const svg = $('.node-wires');
  const outer = nodeVisual.getBoundingClientRect();
  if (!outer.width) return;
  svg.setAttribute('viewBox', '0 0 ' + outer.width + ' ' + outer.height);
  const point = (selector, right, offset = 0) => {
    const box = $(selector, nodeVisual).getBoundingClientRect();
    return { x: (right ? box.right : box.left) - outer.left, y: box.top - outer.top + 35 + offset };
  };
  const connections = [
    [point('.mini-input', true), point('.mini-reverb', false)],
    [point('.mini-input', true), point('.mini-gain', false)],
    [point('.mini-reverb', true), point('.mini-mix', false, -7)],
    [point('.mini-gain', true), point('.mini-mix', false, 7)]
  ];
  svg.replaceChildren(...connections.map(([a, b]) => {
    const line = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    const bend = Math.max(15, (b.x - a.x) * .5);
    line.setAttribute('d', 'M' + a.x + ' ' + a.y + 'C' + (a.x + bend) + ' ' + a.y + ' ' + (b.x - bend) + ' ' + b.y + ' ' + b.x + ' ' + b.y);
    return line;
  }));
}
drawNodeWires();
new ResizeObserver(drawNodeWires).observe(nodeVisual);
document.fonts.ready.then(drawNodeWires);

function toast(message) {
  const element = $('#toast');
  clearTimeout(toastTimer);
  element.textContent = message;
  element.hidden = false;
  toastTimer = setTimeout(() => { element.hidden = true; }, 4000);
}
$('#copy-commands').addEventListener('click', async () => {
  const text = $('#setup-commands').textContent.trim();
  try {
    await navigator.clipboard.writeText(text);
    toast('命令已复制。在便携包解压目录中运行。');
  } catch {
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents($('#setup-commands'));
    selection.removeAllRanges();
    selection.addRange(range);
    toast('无法自动复制，已选中命令；请手动复制。');
  }
});
