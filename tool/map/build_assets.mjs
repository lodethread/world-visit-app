#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';
import { feature, mesh } from 'topojson-client';
import countriesTopo50m from 'world-atlas/countries-50m.json' assert { type: 'json' };
import countriesTopo110m from 'world-atlas/countries-110m.json' assert { type: 'json' };

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..', '..');
const outputDir = join(root, 'assets', 'map');
const placeMasterPath = join(root, 'assets', 'places', 'place_master.json');

function loadPlaceMasterMeta() {
  const raw = readFileSync(placeMasterPath, 'utf8');
  const entries = JSON.parse(raw);
  const metaMap = new Map();
  for (const entry of entries) {
    const geometryId = entry.geometry_id;
    if (!geometryId) continue;
    metaMap.set(String(geometryId), {
      placeCode: entry.place_code,
      drawOrder: Number(entry.draw_order ?? 0),
    });
  }
  return metaMap;
}

function ensureDir(dir) {
  mkdirSync(dir, { recursive: true });
}

function gzipWrite(path, obj) {
  const json = JSON.stringify(obj);
  const gzipped = gzipSync(Buffer.from(json));
  writeFileSync(path, gzipped);
}

function buildCountries(topoJson, placeMeta) {
  const collection = feature(topoJson, topoJson.objects.countries);
  const features = collection.features
    .map((feat) => {
      let id = feat.id;
      const name = feat.properties?.name;
      if (!id && name === 'Kosovo') {
        id = 'XK';
      }
      if (id == null) {
        console.warn(`Skip feature without id (${name ?? 'unknown'})`);
        return null;
      }
      const meta = placeMeta.get(String(id));
      const drawOrder = meta?.drawOrder ?? 0;
      return {
        type: 'Feature',
        id: String(id),
        properties: {
          geometry_id: String(id),
          name,
          place_code: meta?.placeCode,
          draw_order: drawOrder,
        },
        geometry: feat.geometry,
      };
    })
    .filter(Boolean);

  return {
    type: 'FeatureCollection',
    features,
  };
}

function buildBorders() {
  const borderGeometry = mesh(
    countriesTopo50m,
    countriesTopo50m.objects.countries,
    (a, b) => a !== b,
  );
  return {
    type: 'FeatureCollection',
    features: [
      {
        type: 'Feature',
        id: 'world-borders',
        properties: { kind: 'borders' },
        geometry: borderGeometry,
      },
    ],
  };
}

function main() {
  ensureDir(outputDir);
  const placeMeta = loadPlaceMasterMeta();
  const countries50m = buildCountries(countriesTopo50m, placeMeta);
  const countries110m = buildCountries(countriesTopo110m, placeMeta);
  const bordersFc = buildBorders();
  const countries50mPath = join(outputDir, 'countries_50m.geojson.gz');
  const countries110mPath = join(outputDir, 'countries_110m.geojson.gz');
  const bordersPath = join(outputDir, 'borders_50m.geojson.gz');
  gzipWrite(countries50mPath, countries50m);
  gzipWrite(countries110mPath, countries110m);
  gzipWrite(bordersPath, bordersFc);
  console.log(
    `Generated ${countries50m.features.length} countries (50m), ${countries110m.features.length} countries (110m) and borders asset.`,
  );
}

main();
