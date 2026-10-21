export {loadLayoutAssets} from './assets.js';
const defaultMessages = Object.freeze({
  viewerLabel: 'Venue layout', places: 'Places', place: 'Place', standing: 'Standing',
  availableCount: '{count} available', confirmQuantity: 'Confirm quantity', selectedQuantity: 'Selected quantity {count}',
  quantityRejected: 'Quantity rejected', placeUnavailable: 'Place unavailable',
  selectedPlaces: 'Selected {count} places', releasedPlaces: 'Released {count} places',
  selectionRejected: 'Selection rejected', backgroundUnavailable: 'Background resource unavailable',
  placesTogether: '{count} places together', pending: 'pending', available: 'available',
  occupied: 'occupied', reserved: 'reserved', blocked: 'blocked', unavailable: 'unavailable', disabled: 'disabled', sold: 'sold',
});
function message(options, key, values = {}) {
  const template = options.messages?.[key] ?? defaultMessages[key] ?? key;
  return String(template).replace(/\{(\w+)\}/g, (_, name) => String(values[name] ?? `{${name}}`));
}

const kernelLoads = new Map();
const kernelReady = () => globalThis.VenueLayoutKernel?.protocol === 1 &&
  globalThis.VenueLayoutKernel.documentVersion === 2 &&
  globalThis.VenueLayoutKernel.resourceProtocol === 2 &&
  typeof globalThis.VenueLayoutKernel.validate === 'function' &&
  typeof globalThis.VenueLayoutKernel.compileScene === 'function';

/** Load the Dart asset unchanged. Re-bundling it renames runtime type identities. */
export function loadKernel(url) {
  if (kernelReady()) return Promise.resolve();
  if (globalThis.VenueLayoutKernel) return Promise.reject(new Error('Unsupported venue layout kernel protocol'));
  if (typeof document === 'undefined') return Promise.reject(new Error('Kernel script loading requires a browser document'));
  let href;
  try {
    const parsed = new URL(url, document.baseURI);
    if (!['http:', 'https:', 'file:'].includes(parsed.protocol)) throw new Error('Unsupported kernel asset URL');
    href = parsed.href;
  } catch (error) { return Promise.reject(error); }
  if (kernelLoads.has(href)) return kernelLoads.get(href);
  const script = document.createElement('script');
  script.src = href;
  script.async = true;
  const loading = new Promise((resolve, reject) => {
    script.onload = () => kernelReady() ? resolve() : reject(new Error('Invalid venue layout kernel protocol or exports'));
    script.onerror = () => reject(new Error('Venue layout kernel asset could not be loaded'));
  }).finally(() => {
    script.onload = script.onerror = null;
    script.remove();
    kernelLoads.delete(href);
  });
  kernelLoads.set(href, loading);
  document.head.appendChild(script);
  return loading;
}

const SVG = 'http://www.w3.org/2000/svg';
let viewerSerial = 0;
const color = value => /^#[0-9a-f]{8}$/i.test(value || '') ? value : '#00000000';
const element = (tag, attributes = {}) => {
  const node = document.createElementNS(SVG, tag);
  for (const [key, value] of Object.entries(attributes)) if (value != null) node.setAttribute(key, String(value));
  return node;
};
const pathData = path => path.map(command => command.join(' ')).join(' ');
// `meet` may expose world coordinates outside the nominal viewBox. Culling
// must follow the browser's actual viewport rather than treating viewBox as a clip.
function visibleWorldBounds(svg, matrix) {
  const rect = svg.getBoundingClientRect();
  if (!matrix || rect.width <= 0 || rect.height <= 0) return null;
  let inverse;
  try {inverse = matrix.inverse();} catch {return null;}
  const points = [[rect.left, rect.top], [rect.right, rect.top], [rect.left, rect.bottom], [rect.right, rect.bottom]]
    .map(([x, y]) => new DOMPoint(x, y).matrixTransform(inverse));
  if (points.some(p => !Number.isFinite(p.x) || !Number.isFinite(p.y))) return null;
  const xs = points.map(p => p.x), ys = points.map(p => p.y);
  const x = Math.min(...xs), y = Math.min(...ys);
  return {x, y, width: Math.max(...xs) - x, height: Math.max(...ys) - y};
}
/** Mount the shared Dart scene. Geometry, glyphs and hit testing belong to the kernel. */
export function mount(container, options = {}) {
  if (!container || !globalThis.VenueLayoutKernel) throw new Error('Container and VenueLayoutKernel are required');
  const root = document.createElement('div');
  root.className = 'venue-layout-viewer';
  root.style.position = 'relative';
  const svg = element('svg', {role: 'img', 'aria-label': options.accessibilityLabel || message(options, 'viewerLabel'), width: '100%', height: '100%'});
  svg.style.touchAction = 'none';
  svg.style.display = 'block';
  svg.style.minHeight = '240px';
  const list = document.createElement('div');
  list.setAttribute('role', 'list');
  list.setAttribute('aria-label', message(options, 'places'));
  const live = document.createElement('div');
  live.setAttribute('role', 'status'); live.setAttribute('aria-live', 'polite');
  // Preserve keyboard/screen-reader controls without a second visual seat UI.
  for (const assistive of [list, live]) Object.assign(assistive.style, {
    position: 'absolute', top: '0', left: '0', width: '1px', height: '1px',
    overflow: 'hidden', clipPath: 'inset(50%)', whiteSpace: 'nowrap',
    padding: '0', margin: '-1px', border: '0', boxSizing: 'border-box',
  });
  const detail = document.createElement('div');
  root.append(svg, list, detail, live); container.append(root);
  const handle = {serial: ++viewerSerial, container, root, svg, list, detail, live, options: {}, pending: new Set(), selected: new Set(), quantities: new Map(), disposed: false, generation: 0, update(next) {return update(handle, next);}, dispose() {dispose(handle);}, zoomBy(factor) {
    if (handle.disposed) throw new Error('Viewer is disposed');
    if (!Number.isFinite(factor) || factor <= 0) throw new Error('Zoom factor must be positive');
    handle.hideTooltip?.();
    const c = handle.camera, ratio = zoomFactor(handle, c, 1 / factor);
    handle.camera = {...c, x: c.x + c.width * (1 - ratio) / 2, y: c.y + c.height * (1 - ratio) / 2, width: c.width * ratio, height: c.height * ratio};
    render(handle, []);
  }, fitToScreen() {
    if (handle.disposed) throw new Error('Viewer is disposed');
    handle.hideTooltip?.(); handle.camera = null; render(handle, []);
  }};
  handle.click = async event => {
    const inverse = svg.getScreenCTM()?.inverse();
    if (!inverse) return;
    const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(inverse);
    const id = globalThis.VenueLayoutKernel.hitTest(handle.json, point.x, point.y);
    if (handle.suppressClick) {handle.suppressClick = false; return;}
    if (id) await requestSelection(handle, id);
  };
  svg.addEventListener('click', handle.click);
  installCamera(handle);
  installTooltip(handle, options);
  try {update(handle, options);} catch(error) {dispose(handle);throw error;}
  if (typeof ResizeObserver !== 'undefined') {
    handle.resizeObserver = new ResizeObserver(() => {if (!handle.disposed) render(handle, []);});
    handle.resizeObserver.observe(svg);
  }
  return handle;
}
async function requestSelection(handle, id) {
  const {options} = handle;
  const node = options.document.nodes.find(n => n.id === id);
  if (!node) return;
  if (node.kind === 'capacityArea') {
    if(handle.pending.has(id))return;
    const state = options.capacityPresentation?.[id] || {};
    const generation=handle.generation, callback=options.onQuantityRequested;
    handle.detail.replaceChildren();
    const label = document.createElement('label'); label.textContent = `${node.label || message(options, 'standing')} - ${message(options, 'availableCount', {count: state.available ?? state.capacity ?? 0})}`;
    const quantity = document.createElement('input'); quantity.type = 'number'; quantity.min = '0'; quantity.max = String(state.available ?? state.capacity ?? 0); quantity.value = String(handle.quantities.get(id) ?? 0);
    const confirm = document.createElement('button'); confirm.textContent = message(options, 'confirmQuantity');
    confirm.onclick = async () => {
      if(handle.disposed||generation!==handle.generation||handle.pending.has(id))return;
      const current=handle.options.capacityPresentation?.[id]||{};
      const value = Number(quantity.value), available=Number(current.available??current.capacity??0);
      const unavailable=['occupied','unavailable','disabled','blocked','sold','reserved'].includes(current.status)||current.selectable===false;
      if (!Number.isInteger(value) || value < 0 || value > available || (value>0&&unavailable) || !callback) return;
      confirm.disabled = true;handle.pending.add(id);render(handle,[id]);
      try {
        const result = await callback(id, value);
        if (handle.disposed||generation!==handle.generation)return;
        if(result?.accepted)handle.quantities.set(id,value);
        handle.live.textContent = result?.accepted ? message(options, 'selectedQuantity', {count: value}) : result?.message || message(options, 'quantityRejected');
      } catch (error) {if (!handle.disposed&&generation===handle.generation) handle.live.textContent = String(error.message || error);}
      finally {if(!handle.disposed&&generation===handle.generation){handle.pending.delete(id);confirm.disabled=false;render(handle,[id]);}}
    };
    label.append(quantity); handle.detail.append(label, confirm); quantity.focus(); return;
  }
  if (node.kind !== 'seat' || !options.onSelectionRequested) return;
  const unavailable = new Set(['occupied','unavailable','disabled','blocked','sold','reserved']);
  const unit = (options.document.selectionUnits || []).find(u => u.nodeIds.includes(id));
  const ids = unit?.nodeIds || [id];
  if (ids.some(id => unavailable.has(options.seatPresentation?.[id]?.status) || options.seatPresentation?.[id]?.selectable === false)) {handle.live.textContent = message(options, 'placeUnavailable'); return;}
  if (ids.some(id => handle.pending.has(id))) return;
  const selecting = !ids.every(id => handle.selected.has(id));
  const previous = new Set(handle.selected);
  ids.forEach(id => {handle.pending.add(id); selecting ? handle.selected.add(id) : handle.selected.delete(id);});
  const generation = handle.generation;
  render(handle, ids);
  try {
    const result = await options.onSelectionRequested(new Set(ids), selecting);
    if (handle.disposed || generation !== handle.generation) return;
    if (!result?.accepted) ids.forEach(id => previous.has(id) ? handle.selected.add(id) : handle.selected.delete(id));
    handle.live.textContent = result?.accepted ? message(options, selecting ? 'selectedPlaces' : 'releasedPlaces', {count: ids.length}) : result?.message || message(options, 'selectionRejected');
  } catch (error) {if (!handle.disposed && generation === handle.generation) {ids.forEach(id => previous.has(id) ? handle.selected.add(id) : handle.selected.delete(id)); handle.live.textContent = String(error.message || error);}}
  finally {if (!handle.disposed && generation === handle.generation) {ids.forEach(id => handle.pending.delete(id)); render(handle, ids);}}
}
export function update(handle, options = {}) {
  handle.hideTooltip?.();
  if (handle.disposed) throw new Error('Viewer is disposed');
  const resourcesChanged = options.resources && options.resources !== handle.options.resources;
  if (options.document && options.document !== handle.options.document) {const issues=JSON.parse(globalThis.VenueLayoutKernel.validate(JSON.stringify(options.document)));if(issues.length)throw new Error(issues.map(i=>`${i.path}: ${i.reason}`).join('; '));}
  if (resourcesChanged && globalThis.VenueLayoutKernel.validateResources) {const issues=JSON.parse(globalThis.VenueLayoutKernel.validateResources(JSON.stringify(options.resources)));if(issues.length)throw new Error(issues.map(i=>`${i.path}: ${i.reason}`).join('; '));}
  const replacingDocument = options.document && options.document !== handle.options.document;
  handle.options = {...handle.options, ...options};
  if (!handle.options.document) throw new Error('A document is required');
  if (replacingDocument) {handle.generation++; handle.pending.clear(); handle.selected.clear(); handle.quantities.clear(); handle.detail.replaceChildren(); handle.scene = null; handle.sceneItems = null; handle.elements = null; handle.listDocument = null;}
  if (options.seatPresentation) for (const [id,state] of Object.entries(options.seatPresentation)) {
    if (!handle.pending.has(id) && typeof state.selected==='boolean') state.selected ? handle.selected.add(id) : handle.selected.delete(id);
  }
  if(options.capacityPresentation)for(const [id,state] of Object.entries(options.capacityPresentation)) {
    if(!handle.pending.has(id)&&Number.isInteger(state.quantity)&&state.quantity>=0)handle.quantities.set(id,state.quantity);
  }
  if (replacingDocument || !handle.json) handle.json = JSON.stringify(handle.options.document);
  if (resourcesChanged || !handle.resourcesJson) {handle.resourcesJson = JSON.stringify(handle.options.resources || {}); handle.sceneItems = null; handle.elements = null;}
  render(handle);
  return handle;
}
function render(handle, dirtyIds) {
  const {options, svg} = handle;
  const presentation = {...options.seatPresentation, ...options.capacityPresentation};
  for (const id of new Set([...Object.keys(options.seatPresentation || {}),...handle.selected])) presentation[id] = {...presentation[id], selected: handle.selected.has(id)};
  for (const id of handle.pending) presentation[id] = {...presentation[id], pending: true};
  let scene;
  if (handle.sceneItems && globalThis.VenueLayoutKernel.compileSceneNodes) {
    const changed = dirtyIds || [...new Set([...Object.keys(presentation), ...Object.keys(handle.previousPresentation || {})])].filter(id => JSON.stringify(presentation[id]) !== JSON.stringify(handle.previousPresentation?.[id]));
    if (changed.length === 0) {
      scene = handle.scene;
    } else {
    scene = JSON.parse(globalThis.VenueLayoutKernel.compileSceneNodes(handle.json, JSON.stringify(changed), handle.resourcesJson, JSON.stringify(presentation)));
    const changedSet = new Set(changed);
    for (const [id, item] of handle.sceneItems) if (changedSet.has(item.nodeId || item.id)) handle.sceneItems.delete(id);
    for (const item of scene.items) handle.sceneItems.set(item.id, item);
    scene = {...scene, items: [...handle.sceneItems.values()].sort((a, b) => a.paintOrder[0] - b.paintOrder[0] || a.paintOrder[1] - b.paintOrder[1])};
    }
  } else {
    scene = JSON.parse(globalThis.VenueLayoutKernel.compileScene(handle.json, handle.resourcesJson, JSON.stringify(presentation)));
    handle.sceneItems = new Map(scene.items.map(item => [item.id, item]));
  }
  handle.previousPresentation = presentation; handle.scene = scene;
  if (scene.issues.length) {handle.live.textContent = scene.issues.map(i => i.reason).join(', '); options.onIssues?.(scene.issues);}
  const c = scene.canvas;
  if (!handle.camera) handle.camera = {x: c.x || 0, y: c.y || 0, width: c.width, height: c.height};
  handle.camera = boundCamera(handle, handle.camera);
  svg.setAttribute('viewBox', `${handle.camera.x} ${handle.camera.y} ${handle.camera.width} ${handle.camera.height}`);
  svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
  updateCanvasFrame(handle, c);
  const limits = cameraMetrics(handle, handle.camera);
  options.onCameraChanged?.({canZoomIn: handle.camera.width > limits.minWidth + .001, canZoomOut: handle.camera.width < limits.maxWidth - .001});
  if (!handle.elements) {svg.replaceChildren(element('rect', {x: c.x || 0, y: c.y || 0, width: c.width, height: c.height, fill: color(c.fill)})); handle.elements = new Map();}
  const containers=[svg],previous=new Map([[svg,svg.firstElementChild]]);
  const placeNode = node => {const parent=containers.at(-1),before=previous.get(parent)||null;if(node.parentNode!==parent||node.previousSibling!==before)parent.insertBefore(node,before?before.nextSibling:parent.firstChild);previous.set(parent,node);};
  const wanted = new Set(), screenMatrix=svg.getScreenCTM(), zoom=screenMatrix?Math.hypot(screenMatrix.a,screenMatrix.b):1, viewport=visibleWorldBounds(svg, screenMatrix);
  for (const item of scene.items) {
    if (zoom < (item.minZoom || 0)) continue;
    const b = item.cullingBounds || item.bounds, v = viewport;
    if (b && v && (b.x + b.width < v.x || b.y + b.height < v.y || b.x > v.x + v.width || b.y > v.y + v.height)) continue;
    if(item.kind==='vectorRestore'){containers.pop();continue;}
    wanted.add(item.id);
    const old = handle.elements.get(item.id);
    if(item.kind==='vectorClip'||item.kind==='vectorLayer'){
      let group=old?.item===item?old.node:null;
      if(!group){
        group=element('g',{'data-node-id':item.nodeId});
        if(item.kind==='vectorLayer')group.setAttribute('opacity',item.opacity);
        else{
          const id=`venue-${handle.serial}-${item.id.replace(/[^a-zA-Z0-9_-]/g,'-')}-clip`,defs=element('defs'),clip=element('clipPath',{id,clipPathUnits:'userSpaceOnUse'});
          clip.append(element('path',{d:pathData(item.path),'clip-rule':item.fillRule,transform:`matrix(${item.matrix.join(' ')})`}));defs.append(clip);group.append(defs);group.setAttribute('clip-path',`url(#${id})`);
        }
        if(old)old.node.replaceWith(group);handle.elements.set(item.id,{item,node:group});
      }
      placeNode(group);containers.push(group);previous.set(group,item.kind==='vectorClip'?group.firstElementChild:null);continue;
    }
    if (old?.item === item) {placeNode(old.node); continue;}
    const group = element('g', {transform: `matrix(${item.matrix.join(' ')})`, opacity: item.kind === 'image' ? item.opacity ?? 1 : null, 'data-node-id': item.nodeId || item.id});
    if (item.kind === 'image') {
      const asset = options.resources?.assets?.[item.assetRef];
      const href = asset?.url;
      if (href && /^(data:image\/(png|jpeg|webp);base64,|blob:|https?:|file:|\.\.?\/)/i.test(href)) {
        const source = item.sourceRect, destination = item.destinationRect;
        const nested = element('svg', {x: destination.x, y: destination.y, width: destination.width, height: destination.height, viewBox: `${source.x} ${source.y} ${source.width} ${source.height}`, preserveAspectRatio: 'none', overflow: 'hidden'});
        nested.append(element('image', {href, width: item.width, height: item.height}));
        const local = element('g', {transform: group.getAttribute('transform')}); local.append(nested); group.removeAttribute('transform');
        if (item.clip) {const clipId = `venue-${handle.serial}-background-clip`, defs = element('defs'), clip = element('clipPath', {id: clipId, clipPathUnits:'userSpaceOnUse'}); clip.append(element('rect', item.clip)); defs.append(clip); group.append(defs); group.setAttribute('clip-path', `url(#${clipId})`);}
        group.append(local);
      } else {handle.live.textContent = message(options, 'backgroundUnavailable'); options.onIssues?.([{reason: 'asset_unavailable', path: 'background', assetRef: item.assetRef}]);}
    } else {
      const paint=(kind)=>{
        const gradient=item[kind+'Gradient'];if(!gradient)return color(item[kind]);
        const id=`venue-${handle.serial}-${item.id.replace(/[^a-zA-Z0-9_-]/g,'-')}-${kind}`,defs=element('defs');
        const g=gradient.type==='linear'?element('linearGradient',{id,gradientUnits:'userSpaceOnUse',x1:gradient.from[0],y1:gradient.from[1],x2:gradient.to[0],y2:gradient.to[1],spreadMethod:gradient.spread}):element('radialGradient',{id,gradientUnits:'userSpaceOnUse',cx:gradient.center[0],cy:gradient.center[1],r:gradient.radius,fx:gradient.focal?.[0]??gradient.center[0],fy:gradient.focal?.[1]??gradient.center[1],gradientTransform:`matrix(${gradient.matrix.join(' ')})`,spreadMethod:gradient.spread});
        gradient.colors.forEach((c,i)=>g.append(element('stop',{offset:gradient.stops[i],'stop-color':color(c)})));defs.append(g);group.append(defs);return `url(#${id})`;
      };
      if(item.localClip){const id=`venue-${handle.serial}-${item.id.replace(/[^a-zA-Z0-9_-]/g,'-')}-text-clip`,defs=element('defs'),clip=element('clipPath',{id,clipPathUnits:'userSpaceOnUse'});clip.append(element('rect',item.localClip));defs.append(clip);group.append(defs);group.setAttribute('clip-path',`url(#${id})`);}
      group.append(element('path', {d: pathData(item.path || []), fill: paint('fill'), stroke: paint('stroke'), 'fill-rule':item.fillRule||'nonzero', 'stroke-miterlimit':item.miterLimit||4, 'fill-opacity': item.opacity ?? 1, 'stroke-opacity': item.opacity ?? 1, 'stroke-width': item.strokeWidth || 0, 'vector-effect': item.kind === 'floor' ? 'non-scaling-stroke' : null, 'stroke-dasharray': item.dash?.join?.(' '), 'stroke-linecap': item.kind==='state'?'round':item.strokeCap||'butt', 'stroke-linejoin': item.kind==='state'?'round':item.strokeJoin||'miter'}));
    }
    const tooltip = options.seatPresentation?.[item.nodeId || item.id]?.tooltip ?? item.label;
    if (tooltip) {const title = element('title'); title.textContent = tooltip; group.append(title);}
    if (old) old.node.replaceWith(group);
    placeNode(group);
    handle.elements.set(item.id, {item, node: group});
  }
  for (const [id, entry] of handle.elements) if (!wanted.has(id)) {entry.node.remove(); handle.elements.delete(id);}
  if (dirtyIds?.length !== 0) renderList(handle);
}
function installTooltip(handle, options) {
  const tooltip = document.createElement('aside');
  tooltip.className = 'venue-layout-tooltip';
  tooltip.id = `venue-layout-tooltip-${handle.serial}`;
  tooltip.setAttribute('role', 'tooltip');
  tooltip.hidden = true;
  Object.assign(tooltip.style, {
    position: 'fixed', zIndex: '2147483647', pointerEvents: 'none',
    maxWidth: 'min(280px, calc(100vw - 16px))', boxSizing: 'border-box',
    padding: '8px 10px', borderRadius: '6px', background: '#202124',
    color: '#fff', font: '13px/1.4 system-ui, sans-serif', whiteSpace: 'pre-line',
    overflowWrap: 'anywhere', boxShadow: '0 2px 8px #0004', margin: '0',
  });
  Object.assign(tooltip.style, options.tooltipStyle || {});
  // Stay inside the viewer's dialog/top layer; never inject HTML from hosts.
  handle.root.append(tooltip);
  handle.tooltip = tooltip;
  handle.hideTooltip = () => {tooltip.hidden = true; tooltip.textContent = '';};
  handle.hover = event => {
    if (handle.disposed || event.buttons || event.pointerType === 'touch') {
      handle.hideTooltip(); return;
    }
    const inverse = handle.svg.getScreenCTM()?.inverse();
    if (!inverse) {handle.hideTooltip(); return;}
    const point = new DOMPoint(event.clientX, event.clientY).matrixTransform(inverse);
    const id = globalThis.VenueLayoutKernel.hitTest(handle.json, point.x, point.y);
    const node = handle.options.document.nodes.find(node => node.id === id);
    const content = handle.options.seatPresentation?.[id]?.tooltip ?? node?.label;
    if (!content) {handle.hideTooltip(); return;}
    tooltip.textContent = String(content);
    tooltip.hidden = false;
    const bounds = tooltip.getBoundingClientRect();
    const width = globalThis.innerWidth || document.documentElement.clientWidth;
    const height = globalThis.innerHeight || document.documentElement.clientHeight;
    const offset = handle.options.tooltipOffset ?? 15;
    tooltip.style.left = `${Math.max(8, event.clientX + offset + bounds.width > width ? event.clientX - bounds.width - offset : event.clientX + offset)}px`;
    tooltip.style.top = `${Math.max(8, event.clientY + offset + bounds.height > height
      ? event.clientY - bounds.height - offset : event.clientY + offset)}px`;
  };
  handle.tooltipKey = event => {if (event.key === 'Escape') handle.hideTooltip();};
  handle.svg.addEventListener('pointermove', handle.hover);
  for (const name of ['pointerleave', 'pointerdown', 'pointercancel', 'wheel']) {
    handle.svg.addEventListener(name, handle.hideTooltip);
  }
  handle.tooltipWindow = document.defaultView || globalThis;
  handle.tooltipWindow.addEventListener?.('keydown', handle.tooltipKey);
  handle.tooltipWindow.addEventListener?.('scroll', handle.hideTooltip, true);
  handle.tooltipWindow.addEventListener?.('resize', handle.hideTooltip);
}
// Presentation-only canvas framing in CSS pixels, independent of document
// geometry and zoom. Clipping includes imported artwork that covers the fill.
function updateCanvasFrame(handle, canvas) {
  const requested = Number(handle.options.canvasCornerRadius) || 0;
  const svg = handle.svg, matrix = svg.getScreenCTM();
  if (requested <= 0 || !matrix) {svg.style.clipPath = ''; return;}
  const rect = svg.getBoundingClientRect();
  const a = new DOMPoint(canvas.x || 0, canvas.y || 0).matrixTransform(matrix);
  const b = new DOMPoint((canvas.x || 0) + canvas.width, (canvas.y || 0) + canvas.height).matrixTransform(matrix);
  const radius = Math.min(requested, Math.abs(b.x-a.x)/2, Math.abs(b.y-a.y)/2);
  svg.style.clipPath = `inset(${a.y-rect.top}px ${rect.right-b.x}px ${rect.bottom-b.y}px ${a.x-rect.left}px round ${radius}px)`;
}
function cameraMetrics(handle, camera) {
  const canvas = handle.options.document.canvas, rect = handle.svg.getBoundingClientRect();
  const width = rect.width || canvas.width, height = rect.height || canvas.height;
  const fit = Math.min(width / canvas.width, height / canvas.height);
  const aspect = camera.width / camera.height, fitWidth = Math.min(width, height * aspect) / fit;
  return {canvas, width, height, minWidth: fitWidth / (handle.options.maxZoom || 20), maxWidth: fitWidth / (handle.options.minZoom || .9)};
}
function zoomFactor(handle, camera, factor) {
  const limits = cameraMetrics(handle, camera);
  return Math.min(limits.maxWidth, Math.max(limits.minWidth, camera.width * factor)) / camera.width;
}
function boundCamera(handle, camera) {
  const factor = zoomFactor(handle, camera, 1);
  camera = {...camera, x: camera.x + camera.width * (1 - factor) / 2,
    y: camera.y + camera.height * (1 - factor) / 2, width: camera.width * factor, height: camera.height * factor};
  const {canvas, width, height} = cameraMetrics(handle, camera);
  const scale = Math.min(width / camera.width, height / camera.height);
  const viewportWidth = width / scale, viewportHeight = height / scale;
  const shiftX = (viewportWidth - camera.width) / 2, shiftY = (viewportHeight - camera.height) / 2;
  const clampAxis = (position, start, extent, viewport) => {
    // Match Flutter: empty space cannot extend beyond the viewport midpoint.
    const visible = viewport / 2;
    return Math.min(start + extent - visible, Math.max(start + visible - viewport, position));
  };
  return {...camera, x: clampAxis(camera.x - shiftX, canvas.x || 0, canvas.width, viewportWidth) + shiftX,
    y: clampAxis(camera.y - shiftY, canvas.y || 0, canvas.height, viewportHeight) + shiftY};
}
function installCamera(handle) {
  const svg = handle.svg;
  handle.wheel = event => {
    if (!handle.camera) return;
    event.preventDefault();
    const matrix = svg.getScreenCTM(), p = new DOMPoint(event.clientX, event.clientY).matrixTransform(matrix.inverse()), c = handle.camera;
    if (event.shiftKey) {
      const delta = new DOMPoint(event.deltaX || event.deltaY, event.deltaX ? event.deltaY : 0).matrixTransform(matrix.inverse());
      const origin = new DOMPoint(0, 0).matrixTransform(matrix.inverse());
      handle.camera = boundCamera(handle, {...c, x: c.x + delta.x - origin.x, y: c.y + delta.y - origin.y});
      render(handle, []); return;
    }
    // Flutter uses exp(-deltaY / 200); SVG viewBox dimensions scale inversely.
    const factor = zoomFactor(handle, c, Math.exp(event.deltaY / 200));
    handle.camera = {x: p.x + (c.x - p.x) * factor, y: p.y + (c.y - p.y) * factor, width: c.width * factor, height: c.height * factor};
    render(handle, []);
  };
  let start, pinch; const pointers = new Map();
  handle.pointerdown = event => {if (event.button !== 0 && event.button !== 1) return; pointers.set(event.pointerId, {x:event.clientX,y:event.clientY}); if (pointers.size === 2) {const [a,b] = [...pointers.values()]; pinch = {distance:Math.max(1,Math.hypot(a.x-b.x,a.y-b.y)),center:{x:(a.x+b.x)/2,y:(a.y+b.y)/2},camera:{...handle.camera},inverse:svg.getScreenCTM()?.inverse()};} start = {x: event.clientX, y: event.clientY, camera: {...handle.camera}, inverse: svg.getScreenCTM()?.inverse()}; svg.setPointerCapture(event.pointerId);};
  handle.pointermove = event => {if (pointers.has(event.pointerId)) pointers.set(event.pointerId,{x:event.clientX,y:event.clientY}); if (pointers.size === 2 && pinch?.inverse) {const [a,b] = [...pointers.values()], factor=zoomFactor(handle,pinch.camera,pinch.distance/Math.max(1,Math.hypot(a.x-b.x,a.y-b.y))), origin=new DOMPoint(pinch.center.x,pinch.center.y).matrixTransform(pinch.inverse), current=new DOMPoint((a.x+b.x)/2,(a.y+b.y)/2).matrixTransform(pinch.inverse), c=pinch.camera;  handle.camera={x:origin.x+(c.x-origin.x)*factor+(origin.x-current.x),y:origin.y+(c.y-origin.y)*factor+(origin.y-current.y),width:c.width*factor,height:c.height*factor};handle.suppressClick=true;render(handle,[]);return;} if (!start?.inverse) return; const dx = event.clientX - start.x, dy = event.clientY - start.y; if (Math.hypot(dx, dy) < 4) return; const a = new DOMPoint(start.x, start.y).matrixTransform(start.inverse), b = new DOMPoint(event.clientX, event.clientY).matrixTransform(start.inverse); handle.camera = {...start.camera, x: start.camera.x + a.x - b.x, y: start.camera.y + a.y - b.y}; handle.suppressClick = true; render(handle, []);};
  handle.pointerup = event => {pointers.delete(event.pointerId);start = null;pinch = null;};
  svg.addEventListener('wheel', handle.wheel, {passive: false}); svg.addEventListener('pointerdown', handle.pointerdown); svg.addEventListener('pointermove', handle.pointermove); svg.addEventListener('pointerup', handle.pointerup); svg.addEventListener('pointercancel', handle.pointerup);
}
function renderList(handle) {
  const allNodes = handle.listDocument === handle.options.document ? handle.listNodes : handle.options.document.nodes.filter(n => n.kind === 'seat' || n.kind === 'capacityArea');
  handle.listDocument = handle.options.document; handle.listNodes = allNodes;
  const focusIndex = Math.max(0, allNodes.findIndex(n => n.id === (document.activeElement?.dataset?.nodeId || handle.focused)));
  const offset = Math.max(0, focusIndex - 25);
  const nodes = allNodes.slice(offset, offset + 100);
  const previousFocus = document.activeElement?.dataset?.nodeId;
  handle.list.replaceChildren();
  // Roving focus keeps a single tab stop, including large documents.
  const focused = previousFocus || handle.focused || nodes[0]?.id;
  nodes.forEach((node, index) => {
    const button = document.createElement('button');
    button.dataset.nodeId = node.id;
    button.setAttribute('aria-posinset', String(offset + index + 1)); button.setAttribute('aria-setsize', String(allNodes.length));
    const state = handle.options.seatPresentation?.[node.id] || handle.options.capacityPresentation?.[node.id] || {};
    const unit = (handle.options.document.selectionUnits || []).find(u => u.nodeIds.includes(node.id));
    button.textContent = `${state.accessibilityLabel || state.label || node.label || message(handle.options, 'place')}${unit ? ` - ${message(handle.options, 'placesTogether', {count: unit.nodeIds.length})}` : ''} - ${message(handle.options, handle.pending.has(node.id) ? 'pending' : state.status || 'available')}`;
    button.tabIndex = node.id === focused ? 0 : -1;
    button.setAttribute('aria-pressed', String(handle.selected.has(node.id)));
    button.onclick = () => requestSelection(handle, node.id);
    button.onfocus = () => {handle.focused = node.id;};
    button.onkeydown = event => {
      const delta = ['ArrowRight', 'ArrowDown'].includes(event.key) ? 1 : ['ArrowLeft', 'ArrowUp'].includes(event.key) ? -1 : 0;
      if (delta) {event.preventDefault(); const direction = {ArrowRight: 'right', ArrowLeft: 'left', ArrowUp: 'up', ArrowDown: 'down'}[event.key]; const nearest = globalThis.VenueLayoutKernel.nearestNode?.(handle.json, node.id, direction); const target = allNodes.find(n => n.id === nearest) || node; handle.focused = target.id; button.blur(); renderList(handle); handle.list.querySelector(`[data-node-id="${CSS.escape(target.id)}"]`)?.focus();}
    };
    handle.list.append(button);
  });
  // The accessible list is visually collapsible and usable without the drawing.
  handle.list.style.maxHeight = '120px'; handle.list.style.overflow = 'auto';
  if (previousFocus) handle.list.querySelector(`[data-node-id="${CSS.escape(previousFocus)}"]`)?.focus({preventScroll: true});
}
export function dispose(handle) {
  if (handle.disposed) return;
  handle.disposed = true; handle.generation++;
  handle.svg.removeEventListener('click', handle.click);
  handle.svg.removeEventListener('pointermove', handle.hover);
  for (const name of ['pointerleave', 'pointerdown', 'pointercancel', 'wheel']) handle.svg.removeEventListener(name, handle.hideTooltip);
  handle.tooltipWindow?.removeEventListener?.('keydown', handle.tooltipKey);
  handle.tooltipWindow?.removeEventListener?.('scroll', handle.hideTooltip, true);
  handle.tooltipWindow?.removeEventListener?.('resize', handle.hideTooltip);
  handle.hideTooltip?.();
  for (const name of ['wheel','pointerdown','pointermove','pointerup','pointercancel']) handle.svg.removeEventListener(name, handle[name === 'pointercancel' ? 'pointerup' : name]);
  handle.resizeObserver?.disconnect();
  handle.root.remove(); handle.pending.clear();
}
export const protocol = 1;
