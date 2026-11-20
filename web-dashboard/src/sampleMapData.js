// Labelled SAMPLE points for trying the heatmap with many records (not real
// observations). Generated in the browser with a fixed seed, so the same
// points appear every time; filtered with the same rules as the real ones.

const TOWNS = [
  ['San Jose de Buenavista', 10.744, 121.941], ['Sibalom', 10.79, 122.017], ['Hamtic', 10.701, 121.981],
  ['Belison', 10.836, 121.958], ['Patnongon', 10.914, 122.004], ['Bugasong', 11.044, 122.065],
  ['Laua-an', 11.142, 122.042], ['Barbaza', 11.195, 122.039], ['Tibiao', 11.292, 122.035],
  ['Culasi', 11.426, 122.056], ['Sebaste', 11.59, 122.094], ['Pandan', 11.722, 122.096],
  ['Valderrama', 11.003, 122.13], ['San Remigio', 10.833, 122.087], ['Tobias Fornier', 10.515, 121.947],
  ['Anini-y', 10.432, 121.925],
];
const PESTS = [
  ['brown_planthopper', 'Brown Planthopper'],
  ['green_leafhopper', 'Green Leafhopper'],
  ['rice_bug', 'Rice Bug'],
  ['rice_stem_borer', 'Rice Stem Borer'],
];
const LEVELS = ['LOW', 'LOW', 'MEDIUM', 'MEDIUM', 'HIGH'];
const STAGES = ['Vegetative', 'Reproductive', 'Ripening'];
const LAND = ['upland', 'rainfed_lowland', 'irrigated_lowland', 'irrigated_lowland'];

function rng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

let cache = null;

/** 5,000 sample points over the last 120 days, clustered around Antique's towns. */
export function samplePoints(n = 5000) {
  if (cache && cache.length === n) return cache;
  const r = rng(20261116);
  const now = Date.now();
  const out = [];
  for (let i = 0; i < n; i += 1) {
    const [town, lat, lng] = TOWNS[Math.floor(r() * TOWNS.length)];
    // Rough normal spread (~3 km) around the town centre.
    const g = () => (r() + r() + r() - 1.5) * 0.035;
    const [pestKey, pest] = PESTS[Math.floor(r() * PESTS.length)];
    out.push({
      id: -(i + 1),
      sample: true,
      lat: lat + g(),
      lng: lng + g(),
      municipality: town,
      barangay: 'Sample',
      pest_key: pestKey,
      pest,
      is_disease: false,
      level: LEVELS[Math.floor(r() * LEVELS.length)],
      crop_stage: STAGES[Math.floor(r() * STAGES.length)],
      land_type: LAND[Math.floor(r() * LAND.length)],
      count: 1 + Math.floor(r() * 40),
      created_at: new Date(now - Math.floor(r() * 120) * 86400000).toISOString(),
    });
  }
  cache = out;
  return out;
}

/** The same filters the API applies to real points. */
export function filterSample(points, f) {
  return points.filter(
    (p) =>
      (!f.pest || p.pest === f.pest) &&
      (!f.level || p.level === f.level) &&
      (!f.crop_stage || p.crop_stage === f.crop_stage) &&
      (!f.land_type || p.land_type === f.land_type) &&
      (!f.municipality || p.municipality.toLowerCase() === f.municipality.toLowerCase()) &&
      (!f.start || p.created_at.slice(0, 10) >= f.start) &&
      (!f.end || p.created_at.slice(0, 10) <= f.end),
  );
}
