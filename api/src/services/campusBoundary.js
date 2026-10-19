const turf = require('@turf/turf');

// ---------------------------------------------------------------------------
// Campus boundary (polygon) helpers.
//
// Attendance depends on one question: "is this GPS point inside the campus
// polygon?". This file answers it in one place, and refuses to guess when the
// stored polygon is broken, so a bad polygon cannot silently mark students as
// inside or outside.
//
// GeoJSON positions are [longitude, latitude].
// ---------------------------------------------------------------------------

const MIN_AREA_SQUARE_METERS = 1000; // smaller than this is probably a mistake
const MAX_AREA_SQUARE_METERS = 5000000; // 5 km2: larger is probably a mistake
// Rough box around the Philippines, to catch swapped or mistyped coordinates.
const PHILIPPINES_BOX = { minLat: 4, maxLat: 22, minLng: 116, maxLng: 128 };

const isNumber = (value) => typeof value === 'number' && Number.isFinite(value);

const isPosition = (value) =>
  Array.isArray(value) && value.length >= 2 && isNumber(value[0]) && isNumber(value[1]);

const parseStored = (boundary) => {
  if (typeof boundary !== 'string') return boundary;
  try {
    return JSON.parse(boundary);
  } catch (error) {
    return null;
  }
};

// How deeply a coordinates array is nested: a position is 1, a ring 2,
// a polygon 3, a multipolygon 4.
const depthOf = (value) => {
  let depth = 0;
  let current = value;
  while (Array.isArray(current)) {
    depth += 1;
    current = current[0];
  }
  return depth;
};

// Whatever way the boundary was stored, return a list of polygons, where each
// polygon is a list of rings and each ring is a list of [lng, lat].
const extractPolygons = (boundary) => {
  const value = parseStored(boundary);
  if (!value) return [];

  if (Array.isArray(value)) {
    const depth = depthOf(value);
    if (depth === 2) return [[value]];
    if (depth === 3) return [value];
    if (depth === 4) return value;
    return [];
  }

  switch (value.type) {
    case 'Feature':
      return extractPolygons(value.geometry);
    case 'FeatureCollection':
      return (value.features ?? []).flatMap(extractPolygons);
    case 'GeometryCollection':
      return (value.geometries ?? []).flatMap(extractPolygons);
    case 'Polygon':
      return Array.isArray(value.coordinates) ? [value.coordinates] : [];
    case 'MultiPolygon':
      return Array.isArray(value.coordinates) ? value.coordinates : [];
    default:
      return [];
  }
};

// Closes the ring if needed and removes repeated points. Returns null when it
// cannot be a ring (fewer than 3 different points).
const normalizeRing = (ring) => {
  if (!Array.isArray(ring) || !ring.every(isPosition)) return null;
  const points = [];
  for (const position of ring) {
    const previous = points[points.length - 1];
    if (!previous || previous[0] !== position[0] || previous[1] !== position[1]) {
      points.push([position[0], position[1]]);
    }
  }
  if (points.length > 1) {
    const first = points[0];
    const last = points[points.length - 1];
    if (first[0] === last[0] && first[1] === last[1]) points.pop();
  }
  if (points.length < 3) return null;
  return [...points, points[0]];
};

const everyPosition = (polygons) =>
  polygons.flatMap((polygon) => polygon.flatMap((ring) => ring));

// A longitude can be larger than 90, a latitude cannot. If every first value is
// within 90 and some second value is not, latitude and longitude were swapped.
const looksSwapped = (positions) => {
  const valid = positions.filter(isPosition);
  if (valid.length === 0) return false;
  return (
    valid.every((position) => Math.abs(position[0]) <= 90) &&
    valid.some((position) => Math.abs(position[1]) > 90)
  );
};

/**
 * Reads a stored boundary.
 *
 * Returns { feature, problems, warnings, swapped }.
 * `feature` is a GeoJSON Polygon or MultiPolygon feature, or null when the
 * boundary cannot be used. `problems` explain why. `warnings` are things that
 * were repaired or look doubtful.
 */
const parseCampusBoundary = (boundary) => {
  const problems = [];
  const warnings = [];

  const rawPolygons = extractPolygons(boundary);
  if (rawPolygons.length === 0) {
    problems.push('No polygon found. The boundary is empty or not valid GeoJSON.');
    return { feature: null, problems, warnings, swapped: false };
  }

  let swapped = false;
  const allPositions = everyPosition(rawPolygons);
  if (looksSwapped(allPositions)) {
    swapped = true;
    warnings.push(
      'Latitude and longitude look swapped in the saved boundary. They were swapped back for checking; save the boundary again to fix it.'
    );
  }

  const polygons = [];
  for (const rawPolygon of rawPolygons) {
    const rings = [];
    for (const rawRing of rawPolygon) {
      const oriented = swapped && Array.isArray(rawRing)
        ? rawRing.map((p) => (isPosition(p) ? [p[1], p[0]] : p))
        : rawRing;
      const ring = normalizeRing(oriented);
      if (!ring) {
        problems.push('A ring has fewer than 3 different points or contains a value that is not a number.');
        continue;
      }
      rings.push(ring);
    }
    if (rings.length > 0) polygons.push(rings);
  }

  if (polygons.length === 0) {
    return { feature: null, problems, warnings, swapped };
  }

  const outOfRange = everyPosition(polygons).some(
    ([lng, lat]) => Math.abs(lat) > 90 || Math.abs(lng) > 180
  );
  if (outOfRange) {
    problems.push('A point has a latitude beyond 90 or a longitude beyond 180.');
    return { feature: null, problems, warnings, swapped };
  }

  try {
    const feature =
      polygons.length === 1 ? turf.polygon(polygons[0]) : turf.multiPolygon(polygons);
    return { feature, problems, warnings, swapped };
  } catch (error) {
    problems.push(`The polygon could not be built: ${error.message}`);
    return { feature: null, problems, warnings, swapped };
  }
};

// Smallest distance in meters from a point to the edge of the polygon.
const distanceToEdgeMeters = (feature, longitude, latitude) => {
  const point = turf.point([longitude, latitude]);
  const lines = turf.polygonToLine(feature);
  const lineFeatures = lines.type === 'FeatureCollection' ? lines.features : [lines];
  let best = Infinity;
  for (const line of lineFeatures) {
    const nearest = turf.nearestPointOnLine(line, point, { units: 'meters' });
    const distance = nearest.properties.dist;
    if (isNumber(distance) && distance < best) best = distance;
  }
  return best;
};

// True when the point is inside the polygon (the edge counts as inside).
const isInside = (feature, longitude, latitude) =>
  turf.booleanPointInPolygon(turf.point([longitude, latitude]), feature);

/**
 * Where is a GPS reading compared with a campus?
 *
 * Returns { inside, distanceToEdge } where distanceToEdge is in meters and is
 * measured in both directions (how far inside, or how far outside).
 */
const locate = (feature, longitude, latitude) => ({
  inside: isInside(feature, longitude, latitude),
  distanceToEdge: distanceToEdgeMeters(feature, longitude, latitude)
});

/**
 * A full report on one stored boundary, used by the check script.
 */
const analyzeCampusBoundary = (boundary) => {
  const { feature, problems, warnings, swapped } = parseCampusBoundary(boundary);
  const report = {
    usable: Boolean(feature) && problems.length === 0,
    problems: [...problems],
    warnings: [...warnings],
    swapped,
    feature,
    vertices: 0,
    areaSquareMeters: null,
    center: null,
    selfIntersections: 0
  };
  if (!feature) return report;

  report.vertices = everyPosition(
    feature.geometry.type === 'Polygon' ? [feature.geometry.coordinates] : feature.geometry.coordinates
  ).length;
  report.areaSquareMeters = turf.area(feature);

  const center = turf.centroid(feature).geometry.coordinates;
  report.center = { longitude: center[0], latitude: center[1] };

  try {
    report.selfIntersections = turf.kinks(feature).features.length;
  } catch (error) {
    report.warnings.push(`Could not test the polygon for crossing edges: ${error.message}`);
  }
  if (report.selfIntersections > 0) {
    report.problems.push(
      `The edges cross each other at ${report.selfIntersections} place(s). Part of the campus will be counted wrongly.`
    );
    report.usable = false;
  }

  if (report.areaSquareMeters < MIN_AREA_SQUARE_METERS) {
    report.warnings.push(
      `The area is only ${Math.round(report.areaSquareMeters)} m2. That is smaller than a typical campus.`
    );
  }
  if (report.areaSquareMeters > MAX_AREA_SQUARE_METERS) {
    report.warnings.push(
      `The area is ${(report.areaSquareMeters / 1e6).toFixed(2)} km2. That is larger than a typical campus.`
    );
  }
  const { minLat, maxLat, minLng, maxLng } = PHILIPPINES_BOX;
  if (
    report.center.latitude < minLat ||
    report.center.latitude > maxLat ||
    report.center.longitude < minLng ||
    report.center.longitude > maxLng
  ) {
    report.warnings.push(
      'The center is outside the Philippines. Latitude or longitude may be mistyped or swapped.'
    );
  }
  return report;
};

module.exports = {
  parseCampusBoundary,
  analyzeCampusBoundary,
  isInside,
  locate,
  distanceToEdgeMeters
};
