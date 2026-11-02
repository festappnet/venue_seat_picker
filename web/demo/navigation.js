export function editorLocation(preview, savedLocation) {
  const fallback = new URL('../../', preview);
  if (fallback.pathname === '/') fallback.pathname = '/flutter/';
  if (!savedLocation) return fallback;
  try {
    const saved = new URL(savedLocation, preview);
    return saved.origin === preview.origin ? saved : fallback;
  } catch {
    return fallback;
  }
}
