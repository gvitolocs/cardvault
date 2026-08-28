#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const { routeDefinitions } = require('../server/api-route-manifest');

const ROOT_DIR = path.resolve(__dirname, '..');
const API_DIR = path.join(ROOT_DIR, 'api');
const COVERAGE_PATH = path.join(ROOT_DIR, 'workflows', 'api-route-test-coverage.json');

function readCoverageBaseline() {
  return JSON.parse(fs.readFileSync(COVERAGE_PATH, 'utf8'));
}

function directTestPath(routeFile) {
  const stem = routeFile.replace(/\.js$/, '');
  return path.join(API_DIR, `${stem}.test.js`);
}

function main() {
  const baseline = readCoverageBaseline();
  const covered = baseline.coveredRouteExceptions || {};
  const manifestFiles = new Set(routeDefinitions.map((route) => route.file));
  const errors = [];

  for (const route of routeDefinitions) {
    if (fs.existsSync(directTestPath(route.file))) {
      continue;
    }
    const exception = covered[route.file];
    if (!exception) {
      errors.push(`${route.file} (${route.path}) has no direct test and no coverage baseline entry.`);
      continue;
    }
    if (exception.path !== route.path) {
      errors.push(`${route.file} coverage baseline path is ${exception.path}, expected ${route.path}.`);
    }
    if (!exception.reason || exception.reason.length < 12) {
      errors.push(`${route.file} coverage baseline needs a concrete reason.`);
    }
    if (!Array.isArray(exception.coveredBy) || exception.coveredBy.length === 0) {
      errors.push(`${route.file} coverage baseline must list coveredBy checks.`);
    }
  }

  for (const file of Object.keys(covered)) {
    if (!manifestFiles.has(file)) {
      errors.push(`${file} is in ${path.relative(ROOT_DIR, COVERAGE_PATH)} but is not in the manifest.`);
    }
  }

  if (errors.length) {
    console.error('API route test coverage check failed:');
    for (const error of errors) {
      console.error(`- ${error}`);
    }
    process.exit(1);
  }

  const directCount = routeDefinitions.filter((route) => fs.existsSync(directTestPath(route.file))).length;
  const baselineCount = routeDefinitions.length - directCount;
  console.log(`API route test coverage OK: ${directCount} direct route tests, ${baselineCount} baseline-covered legacy routes.`);
}

main();
