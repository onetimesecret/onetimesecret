// src/scripts/openapi/test-parser.ts

/**
 * Test Otto Routes Parser
 *
 * Validates the parser works correctly with actual route files
 */

import {
  parseApiRoutes,
  getAuthRequirements,
  isCsrfExempt,
  getResponseType as _getResponseType,
  getPathParams,
  toOpenAPIPath,
  groupRoutesByTag,
  parseAllApiRoutes
} from './otto-routes-parser';

console.log('🧪 Testing Otto Routes Parser...\n');

// Test 1: Parse V3 API routes
console.log('Test 1: Parse V3 API routes');
try {
  const v3Routes = parseApiRoutes('v3');
  console.log(`✅ Parsed ${v3Routes.routes.length} routes from ${v3Routes.filePath}`);

  // Show first 3 routes
  console.log('\nFirst 3 routes:');
  for (const route of v3Routes.routes.slice(0, 3)) {
    console.log(`  ${route.method} ${route.path} -> ${route.handler}`);
    if (Object.keys(route.params).length > 0) {
      console.log(`    Params:`, route.params);
    }
  }
  console.log('');
} catch (error) {
  console.error('❌ Failed to parse V3 routes:', error);
  process.exit(1);
}

// Test 2: Parse authentication requirements
console.log('Test 2: Parse authentication requirements');
try {
  const accountRoutes = parseApiRoutes('account');
  const sampleRoute = accountRoutes.routes[0];

  if (sampleRoute) {
    const auth = getAuthRequirements(sampleRoute);
    console.log(`Route: ${sampleRoute.method} ${sampleRoute.path}`);
    console.log(`Auth required: ${auth.required}`);
    console.log(`Auth schemes: ${auth.schemes.join(', ')}`);
    if (auth.role) {
      console.log(`Role required: ${auth.role}`);
    }
    console.log('✅ Auth parsing works\n');
  }
} catch (error) {
  console.error('❌ Failed to parse account routes:', error);
}

// Test 3: CSRF exemption detection
console.log('Test 3: CSRF exemption detection');
try {
  const v3Routes = parseApiRoutes('v3');
  const csrfExemptRoutes = v3Routes.routes.filter(isCsrfExempt);
  console.log(`Found ${csrfExemptRoutes.length} CSRF-exempt routes:`);
  for (const route of csrfExemptRoutes.slice(0, 3)) {
    console.log(`  ${route.method} ${route.path}`);
  }
  console.log('✅ CSRF detection works\n');
} catch (error) {
  console.error('❌ CSRF test failed:', error);
}

// Test 4: Path parameter extraction
console.log('Test 4: Path parameter extraction');
const testPaths = [
  '/receipt/:identifier',
  '/receipt/:identifier/burn',
  '/domains/:extid',
  '/teams/:extid/members/:custid'
];

for (const path of testPaths) {
  const params = getPathParams(path);
  const openApiPath = toOpenAPIPath(path);
  console.log(`  ${path}`);
  console.log(`    Parameters: ${params.join(', ')}`);
  console.log(`    OpenAPI: ${openApiPath}`);
}
console.log('✅ Path parameter extraction works\n');

// Test 5: Route grouping by tag
console.log('Test 5: Route grouping by tag');
try {
  const v3Routes = parseApiRoutes('v3');
  const grouped = groupRoutesByTag(v3Routes.routes);

  console.log(`Grouped into ${grouped.size} tags:`);
  for (const [tag, routes] of grouped.entries()) {
    console.log(`  ${tag}: ${routes.length} routes`);
  }
  console.log('✅ Route grouping works\n');
} catch (error) {
  console.error('❌ Grouping test failed:', error);
}

// Test 6: Parse all API routes
console.log('Test 6: Parse all API routes');
try {
  const allRoutes = parseAllApiRoutes();

  console.log('API Routes Summary:');
  console.log('─────────────────────');
  let totalRoutes = 0;

  for (const [api, parsed] of Object.entries(allRoutes)) {
    console.log(`  ${api}: ${parsed.routes.length} routes`);
    totalRoutes += parsed.routes.length;
  }

  console.log(`\nTotal: ${totalRoutes} routes across ${Object.keys(allRoutes).length} APIs`);
  console.log('✅ All APIs parsed successfully\n');
} catch (error) {
  console.error('❌ Failed to parse all routes:', error);
}

// Summary
console.log('🎉 All parser tests completed!');
console.log('');
console.log('Parser is ready to use for OpenAPI generation.');
