import { test } from 'node:test';
import assert from 'node:assert/strict';
import { editorLocation } from '../demo/navigation.js';

test('preview returns to project Pages and the standalone kit', () => {
  const pages = new URL('https://festappnet.github.io/venue_seat_picker/js/demo/?editor=token');
  assert.equal(editorLocation(pages).href, 'https://festappnet.github.io/venue_seat_picker/');
  assert.equal(editorLocation(new URL('http://localhost:8000/js/demo/')).href, 'http://localhost:8000/flutter/');
  assert.equal(editorLocation(pages, '/venue_seat_picker/?locale=cs').search, '?locale=cs');
  assert.equal(editorLocation(pages, 'https://other.example/').href, 'https://festappnet.github.io/venue_seat_picker/');
});
