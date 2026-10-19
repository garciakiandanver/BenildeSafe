#!/usr/bin/env node
// ---------------------------------------------------------------------------
// Checks the campus polygons saved in the database.
//
//   node scripts/check-campus-polygons.js
//       Report on every campus: usable or not, number of points, area, center,
//       crossing edges, swapped latitude/longitude, and other doubtful things.
//
//   node scripts/check-campus-polygons.js --geojson
//       Prints all boundaries as GeoJSON. Paste it into https://geojson.io to
//       see the polygon on a satellite map and compare it with the real campus.
//
//   node scripts/check-campus-polygons.js --point 14.5635,120.9940 [--accuracy 20]
//       Tests one GPS point (latitude,longitude): which campus it is in, how far
//       it is from the edge in meters, and what time in / the outside timer
//       would do with it. Stand at a gate, read the coordinates, and test them.
//
// To check the cloud (Neon) database instead of your local one:
//   PowerShell:  $env:NODE_ENV="production"; $env:DATABASE_URL="<neon url>"; node scripts/check-campus-polygons.js
//   bash:        NODE_ENV=production DATABASE_URL="<neon url>" node scripts/check-campus-polygons.js
// ---------------------------------------------------------------------------

const { analyzeCampusBoundary, locate } = require('../src/services/campusBoundary');

const MAX_GPS_ACCURACY_METERS =
  Number(process.env.MAX_GPS_ACCURACY_METERS) > 0
    ? Number(process.env.MAX_GPS_ACCURACY_METERS)
    : 100;

const readOption = (argv, name) => {
  const index = argv.indexOf(name);
  return index >= 0 ? argv[index + 1] : undefined;
};

const squareMeters = (value) =>
  value >= 1e6 ? `${(value / 1e6).toFixed(2)} km2` : `${Math.round(value).toLocaleString('en-US')} m2`;

const describePoint = (analysis, latitude, longitude, accuracy) => {
  const position = locate(analysis.feature, longitude, latitude);
  const meters = Math.round(position.distanceToEdge * 10) / 10;
  const lines = [
    position.inside
      ? `  INSIDE, ${meters} m from the nearest edge`
      : `  OUTSIDE, ${meters} m from the nearest edge`
  ];
  if (accuracy === null) {
    lines.push('  (add --accuracy <meters> to see how the app would treat this reading)');
    return lines;
  }
  if (accuracy > MAX_GPS_ACCURACY_METERS) {
    lines.push(`  Accuracy ${accuracy} m is weaker than ${MAX_GPS_ACCURACY_METERS} m: time in is refused, and the reading is ignored while timed in.`);
  } else if (!position.inside && position.distanceToEdge <= accuracy) {
    lines.push(`  Only ${meters} m outside with a ${accuracy} m error: too close to call. The outside timer does NOT start.`);
  } else if (position.inside && position.distanceToEdge <= accuracy) {
    lines.push(`  Only ${meters} m inside with a ${accuracy} m error: time in works, but it will not cancel a running outside timer.`);
  } else {
    lines.push(position.inside ? '  Clearly inside.' : '  Clearly outside: the outside timer starts.');
  }
  return lines;
};

const run = async ({ pool, argv = process.argv.slice(2), log = console.log } = {}) => {
  const result = await pool.query(`
    SELECT id, campus_code, campus_name, boundary_coordinates
    FROM campuses
    ORDER BY campus_name
  `);

  if (result.rows.length === 0) {
    log('There are no campuses in the database.');
    return { exitCode: 1 };
  }

  const analyses = result.rows.map((campus) => ({
    campus,
    analysis: analyzeCampusBoundary(campus.boundary_coordinates)
  }));

  if (argv.includes('--geojson')) {
    const features = analyses
      .filter(({ analysis }) => analysis.feature)
      .map(({ campus, analysis }) => ({
        ...analysis.feature,
        properties: { campus_code: campus.campus_code, campus_name: campus.campus_name }
      }));
    log(JSON.stringify({ type: 'FeatureCollection', features }, null, 2));
    return { exitCode: 0 };
  }

  const pointText = readOption(argv, '--point');
  if (pointText !== undefined) {
    const [latitude, longitude] = String(pointText).split(',').map((part) => Number(part.trim()));
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      log('Use --point <latitude>,<longitude>, for example --point 14.5635,120.9940');
      return { exitCode: 1 };
    }
    const accuracyText = readOption(argv, '--accuracy');
    const accuracy = accuracyText === undefined ? null : Number(accuracyText);
    if (accuracy !== null && !(Number.isFinite(accuracy) && accuracy >= 0)) {
      log('--accuracy must be a number of meters, for example --accuracy 20');
      return { exitCode: 1 };
    }

    log(`Point ${latitude}, ${longitude}${accuracy === null ? '' : `, accuracy ${accuracy} m`}\n`);
    let found = false;
    for (const { campus, analysis } of analyses) {
      if (!analysis.feature) {
        log(`${campus.campus_name} (${campus.campus_code}): boundary cannot be used, skipped.`);
        continue;
      }
      const position = locate(analysis.feature, longitude, latitude);
      if (position.inside) found = true;
      log(`${campus.campus_name} (${campus.campus_code})`);
      describePoint(analysis, latitude, longitude, accuracy).forEach((line) => log(line));
    }
    if (!found) log('\nThis point is not inside any campus.');
    return { exitCode: 0 };
  }

  let problemCount = 0;
  for (const { campus, analysis } of analyses) {
    log(`${campus.campus_name} (${campus.campus_code})`);
    if (!analysis.feature) {
      log('  UNUSABLE: students cannot time in here.');
    } else {
      log(`  ${analysis.usable ? 'OK' : 'HAS PROBLEMS'}`);
      log(`  ${analysis.vertices} points, area ${squareMeters(analysis.areaSquareMeters)}`);
      log(
        `  center ${analysis.center.latitude.toFixed(6)}, ${analysis.center.longitude.toFixed(6)}`
      );
    }
    analysis.problems.forEach((text) => log(`  PROBLEM: ${text}`));
    analysis.warnings.forEach((text) => log(`  WARNING: ${text}`));
    if (!analysis.usable) problemCount += 1;
    log('');
  }

  log(
    problemCount === 0
      ? `All ${analyses.length} campus polygon(s) can be used.`
      : `${problemCount} of ${analyses.length} campus polygon(s) have problems.`
  );
  log('Tip: run with --geojson and paste the result into https://geojson.io to compare the polygon with the real campus on a satellite map.');
  return { exitCode: problemCount === 0 ? 0 : 1 };
};

module.exports = { run };

if (require.main === module) {
  const pool = require('../src/config/database');
  run({ pool })
    .then(({ exitCode }) => pool.end().then(() => process.exit(exitCode)))
    .catch(async (error) => {
      console.error('Could not check the campuses:', error.message);
      try { await pool.end(); } catch (ignored) { /* nothing to close */ }
      process.exit(1);
    });
}
