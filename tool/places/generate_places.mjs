#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';
import crypto from 'node:crypto';
import countries from 'i18n-iso-countries';

const __dirname = dirname(fileURLToPath(import.meta.url));
const rootDir = resolve(__dirname, '..', '..');
const mapAssetPath = join(rootDir, 'assets', 'map', 'countries_50m.geojson.gz');
const placesDir = join(rootDir, 'assets', 'places');
const contestedTerritories = new Set(['HK', 'MO', 'PR', 'TW', 'PS', 'EH', 'XK']);
const manualPlace = {
  place_code: 'XNC',
  type: 'special',
  name_en: 'Keikoku',
  name_ja: 'Keikoku',
  is_active: false,
  geometry_id: 'XNC',
};
const aliasExtras = {
  HK: ['Hongkong', 'Hong Kong SAR'],
  MO: ['Macau', 'Macao SAR'],
  PR: ['Puerto Rico'],
  TW: ['Taiwan', 'Republic of China'],
  PS: ['Palestine', 'State of Palestine'],
  EH: ['Western Sahara'],
  XK: ['Kosova', 'Republic of Kosovo'],
};

function loadGeoJsonFeatures() {
  const raw = readFileSync(mapAssetPath);
  const decoded = gunzipSync(raw).toString('utf-8');
  const data = JSON.parse(decoded);
  if (!Array.isArray(data.features)) {
    throw new Error('GeoJSON features are missing');
  }
  return data.features;
}

function numericToIso2(geometryId) {
  if (!geometryId) {
    return null;
  }
  if (geometryId === 'XK') {
    return 'XK';
  }
  const padded = geometryId.toString().padStart(3, '0');
  const iso = countries.numericToAlpha2(padded);
  return iso ? iso.toUpperCase() : null;
}

function buildPlaces(features) {
  const placeMap = new Map();
  for (const feature of features) {
    const geometryId = feature?.id?.toString();
    const iso2 = numericToIso2(geometryId);
    if (!iso2) {
      continue;
    }
    if (placeMap.has(iso2)) {
      continue;
    }
    const name = (feature?.properties?.name ?? iso2).trim();
    placeMap.set(iso2, {
      place_code: iso2,
      type: contestedTerritories.has(iso2) ? 'territory' : 'sovereign',
      name_en: name,
      name_ja: name,
      is_active: true,
      geometry_id: geometryId,
    });
  }
  const codes = Array.from(placeMap.keys()).sort();
  const places = codes.map((code, index) => {
    const entry = placeMap.get(code);
    const sortOrder = (index + 1) * 10;
    const drawBase = contestedTerritories.has(code) ? 2_000_000 : 1_000_000;
    return {
      ...entry,
      sort_order: sortOrder,
      draw_order: drawBase + sortOrder,
    };
  });

  const nextSortOrder = (places.at(-1)?.sort_order ?? 0) + 10;
  places.push({
    ...manualPlace,
    sort_order: nextSortOrder,
    draw_order: 3_000_000 + nextSortOrder,
  });
  return places;
}

function normalizeAlias(value) {
  return value?.trim();
}

function buildAliases(places) {
  const aliases = {};
  for (const place of places) {
    const set = new Set();
    set.add(place.place_code);
    set.add(normalizeAlias(place.name_en));
    const noParen = place.name_en.replace(/\s*\(.*?\)\s*/g, '').trim();
    if (noParen && noParen !== place.name_en) {
      set.add(noParen);
    }
    aliasExtras[place.place_code]?.forEach((extra) => {
      const normalized = normalizeAlias(extra);
      if (normalized) {
        set.add(normalized);
      }
    });
    aliases[place.place_code] = Array.from(set).filter(Boolean);
  }
  if (!aliases.XNC) {
    aliases.XNC = ['Keikoku'];
  }
  return aliases;
}

function writeJson(path, data) {
  writeFileSync(path, `${JSON.stringify(data, null, 2)}\n`);
}

function buildMeta(masterContent) {
  const hash = crypto.createHash('sha256').update(masterContent).digest('hex');
  const revision = new Date().toISOString().slice(0, 10);
  return {
    hash: `world-pack-${hash.slice(0, 16)}`,
    revision,
  };
}

function main() {
  const features = loadGeoJsonFeatures();
  const places = buildPlaces(features);
  const aliases = buildAliases(places);
  const masterJson = JSON.stringify(places, null, 2);
  const meta = buildMeta(masterJson);

  writeJson(join(placesDir, 'place_master.json'), places);
  writeJson(join(placesDir, 'place_aliases.json'), aliases);
  writeJson(join(placesDir, 'place_master_meta.json'), meta);
  console.log(`Generated ${places.length} places.`);
  console.log(`Meta hash: ${meta.hash}`);
}

main();
