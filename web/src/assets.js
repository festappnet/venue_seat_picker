/** Resolve portable raster resources before mounting the synchronous viewer.
 * The host supplies URLs; no backend or asset catalog is owned by this package.
 */
export async function loadLayoutAssets(resources = {}, options = {}) {
  const {fetch: fetcher = globalThis.fetch, signal, maxBytes = 20_000_000} = options;
  const assets = {};
  for (const [ref, asset] of Object.entries(resources.assets || {})) {
    signal?.throwIfAborted();
    if (!asset || !/^[0-9a-f]{64}$/.test(asset.hash) ||
        !['image/png', 'image/jpeg', 'image/webp'].includes(asset.mimeType) ||
        !Number.isSafeInteger(asset.width) || !Number.isSafeInteger(asset.height) ||
        asset.width <= 0 || asset.height <= 0 || asset.width * asset.height > 40_000_000 ||
        !Number.isSafeInteger(asset.byteLength) || asset.byteLength < 1 || asset.byteLength > maxBytes ||
        (ref.startsWith('image:') && ref !== `image:${asset.hash}`)) {
      throw new Error('invalid_asset_manifest');
    }
    let bytes;
    if (asset.data && asset.mime === asset.mimeType) {
      if (asset.data.length > Math.ceil(maxBytes / 3) * 4 + 4) throw new Error('asset_size_limit');
      bytes = Uint8Array.from(atob(asset.data), c => c.charCodeAt(0));
    } else {
      const url = new URL(asset.url, globalThis.location?.href);
      if (!['http:', 'https:', 'data:'].includes(url.protocol)) throw new Error('invalid_asset_url');
      const response = await fetcher(url, {signal, credentials: 'omit', cache: 'force-cache'});
      if (!response.ok) throw new Error('asset_load_failed');
      if (Number(response.headers.get('content-length')) > maxBytes) throw new Error('asset_size_limit');
      const chunks = []; let length = 0;
      const reader = response.body.getReader();
      try {
        for (;;) {
          const {value, done} = await reader.read();
          if (done) break;
          length += value.byteLength;
          if (length > maxBytes || length > asset.byteLength) throw new Error('asset_size_limit');
          chunks.push(value);
        }
      } finally { await reader.cancel(); reader.releaseLock(); }
      bytes = new Uint8Array(length); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    }
    if (bytes.byteLength !== asset.byteLength) throw new Error('asset_length_mismatch');
    const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)),
      b => b.toString(16).padStart(2, '0')).join('');
    if (hash !== asset.hash) throw new Error('asset_hash_mismatch');
    const bitmap = await createImageBitmap(new Blob([bytes], {type: asset.mimeType}));
    try {
      if (bitmap.width !== asset.width || bitmap.height !== asset.height) throw new Error('asset_dimensions_mismatch');
    } finally { bitmap.close(); }
    signal?.throwIfAborted();
    let binary = '';
    for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
    assets[ref] = {...asset, mime: asset.mimeType, data: btoa(binary)};
  }
  return Object.keys(assets).length ? {...resources, assets} : resources;
}
