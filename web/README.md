# Shared venue layout runtime

Build with `../tool/build_web.sh` from a checkout with FVM Flutter 3.47.2.
Load `dist/venue_layout_kernel.js` as a script, then import `mount` from the
public `src/index.js` entry. The Dart-compiled kernel owns all geometry,
text paths and hit tests; this adapter only draws its display list as SVG.

```js
import {mount} from './src/index.js';
const handle = mount(document.querySelector('#plan'), {
  document: layout, resources,
  onSelectionRequested: async (ids, selecting) => ({accepted: true}),
});
handle.update({seatPresentation: nextPresentation});
// Availability changes preserve document geometry and camera.
handle.dispose();
```

Resources use local font outlines and image data. The demo is in `demo/`.
No CDN, Flutter runtime, backend or account is required by the JS consumer.
A host owns reservations, prices, capacity and authoritative validation.
`npm pack --dry-run` checks package contents; it does not publish.

Bundler consumers load the shared Dart kernel once before mounting:

```js
import kernelUrl from "@festapp/venue-layout/kernel?url"; // Vite asset URL
import {loadKernel, mount} from "@festapp/venue-layout";
await loadKernel(kernelUrl);
const handle = mount(container, {document: layout, resources});
```

The kernel must remain an unchanged classic script asset. Do not import its
JavaScript as a module or pass it through a minifier: generated Dart runtime type
identities depend on constructor names. Other bundlers should copy the exported
`@festapp/venue-layout/kernel` file to an asset URL and pass that URL to
`loadKernel`. Concurrent calls for the same URL share one request; failed loads
reject and may be retried. Direct browser `<script src>` loading remains valid.

For portable image manifests, resolve processed raster bytes before mounting:

```js
import {loadLayoutAssets, mount} from '@festapp/venue-layout';
const abort = new AbortController();
const resolved = await loadLayoutAssets(resources, {signal: abort.signal});
const viewer = mount(container, {document: layout, resources: resolved});
// When closing during load, abort.abort(); after mounting, viewer.dispose().
```

The resolver verifies bounded byte length, SHA256 and actual decoded dimensions,
then supplies immutable inline raster data to the synchronous renderer. It owns
no uploader, image catalog or backend credentials. The host supplies resource
URLs and persists only its trusted manifest/document; decoded images are transient.
Empty resources remain protocol-neutral; nonempty resources follow kernel protocol1.
