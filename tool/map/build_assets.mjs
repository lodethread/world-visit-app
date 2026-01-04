#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';
import { feature, mesh } from 'topojson-client';
import countriesTopo from 'world-atlas/countries-50m.json' assert { type: 'json' };

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

function buildCountries(placeMeta) {
  const collection = feature(countriesTopo, countriesTopo.objects.countries);
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
    countriesTopo,
    countriesTopo.objects.countries,
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
  const countriesFc = buildCountries(placeMeta);
  const bordersFc = buildBorders();
  const countriesPath = join(outputDir, 'countries_50m.geojson.gz');
  const bordersPath = join(outputDir, 'borders_50m.geojson.gz');
  gzipWrite(countriesPath, countriesFc);
  gzipWrite(bordersPath, bordersFc);
  console.log(
    `Generated ${countriesFc.features.length} countries and borders asset.`,
  );
}

main();
