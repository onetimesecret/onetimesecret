// scripts/globes/make-globe.mjs
//
// Font-Awesome-style "earth-*" globe icons, generated entirely as vectors.
// Icons are defined in presets.mjs and built by build.mjs.
//
// Pipeline (pure JS, no native code, no rasterising)
//   Natural Earth 1:50m land and countries (world-atlas, public domain)
//   -> d3-geo orthographic projection, clipped *on the sphere* to the cap that
//      exactly fills the r=208 inner disc (the rim used by fa6-solid-earth-*)
//   -> grow, then Clipper morphology with round joins: a closing that merges
//      islands and fills straits, then an opening that removes spits, necks
//      and islands narrower than 2 * open
//   -> Gaussian smoothing along each coastline (the vector counterpart of
//      blur-and-threshold), then drop anything smaller than minArea
//   -> Douglas-Peucker, then a closed quadratic B-spline through the midpoints,
//      written as relative whole-unit coordinates
//   -> cut out of a solid r=256 disc with fill-rule="evenodd".
//
// Preset options
//   center     [lon, lat] the globe faces (required)
//   zoom       1 = whole hemisphere fills the disc; >1 zooms in (default 1)
//   smooth     Gaussian sigma along the coast, in 512-unit space (default 7)
//   open       opening radius (default 0.6 * smooth); lower it for narrow
//              countries whose necks would otherwise be cut (Japan, NZ)
//   grow       outward offset applied before smoothing; fattens narrow land (default 0)
//   minArea    drop islands and lakes smaller than this, in 512-unit² (default 300)
//   focus      country names as in world-atlas; kept at full contrast while
//              all other land is drawn at `dim` opacity
//   dim        opacity of non-focus land (default 0.5)
//   tolerance  curve simplification in 512 units; bigger = fewer bytes (default 1.5)
//   pin        for countries too small to see: radius of a focus-coloured dot
//              at the focus centroid (default 0 = off)
//   pinGap     width of an ocean-coloured ring separating the dot from land (default 0)

import { readFileSync } from 'node:fs';
import { geoCentroid, geoOrthographic, geoPath } from 'd3-geo';
import { feature } from 'topojson-client';
import ClipperLib from 'clipper-lib';

const { Clipper, ClipperOffset, ClipType, PolyType, PolyFillType, JoinType, EndType } = ClipperLib;

const S = 100; // Clipper works in integers: 0.01-unit precision
const INNER_R = 208;
const CLOSE = 0.6; // closing radius as a fraction of the opening radius
const DISC = 'M0 256a256 256 0 1 1 512 0a256 256 0 1 1-512 0Z';

const atlas = (f) => JSON.parse(readFileSync(new URL(`./node_modules/world-atlas/${f}`, import.meta.url)));
const landTopo = atlas('land-50m.json');
const LAND = feature(landTopo, landTopo.objects.land);
const countryTopo = atlas('countries-50m.json');

const countries = (names) => ({
  type: 'FeatureCollection',
  features: names.map((name) => {
    const g = countryTopo.objects.countries.geometries.find((c) => c.properties.name === name);
    if (!g) throw new Error(`country not found in world-atlas: ${name}`);
    return feature(countryTopo, g);
  }),
});

// Polygon operations (Clipper paths: arrays of {X, Y} in S-scaled integers)

const boolean = (type, subject, clip, fill = PolyFillType.pftNonZero) => {
  const c = new Clipper();
  c.AddPaths(subject, PolyType.ptSubject, true);
  if (clip) c.AddPaths(clip, PolyType.ptClip, true);
  const out = [];
  c.Execute(type, out, fill, fill);
  return out;
};
const union = (p, fill) => boolean(ClipType.ctUnion, p, null, fill);
const intersect = (a, b) => boolean(ClipType.ctIntersection, a, b);
const subtract = (a, b) => boolean(ClipType.ctDifference, a, b);

const offset = (paths, d) => {
  if (!d) return paths;
  const o = new ClipperOffset(2, 0.25 * S);
  o.AddPaths(paths, JoinType.jtRound, EndType.etClosedPolygon);
  const out = [];
  o.Execute(out, d * S);
  return out;
};

// closing (+c, -c) then opening (-r, +r), with the two middle steps merged
const morph = (paths, r) => offset(offset(offset(paths, r * CLOSE), -r * (1 + CLOSE)), r);

// Gaussian smoothing along each ring (resampled every unit, circular
// convolution of x and y): the vector counterpart of blur-and-threshold.
// It flattens wiggles that morphology leaves alone; union() afterwards
// repairs any overlap it introduces.
const gauss = (paths, sigma) => {
  if (!sigma) return paths;
  const h = 1 * S;
  const out = paths.map((ring) => {
    const n0 = ring.length;
    const pts = [];
    let carry = 0;
    for (let i = 0; i < n0; i++) {
      const a = ring[i];
      const b = ring[(i + 1) % n0];
      const len = Math.hypot(b.X - a.X, b.Y - a.Y);
      let t = carry;
      while (t < len) {
        pts.push([a.X + ((b.X - a.X) * t) / len, a.Y + ((b.Y - a.Y) * t) / len]);
        t += h;
      }
      carry = t - len;
    }
    const n = pts.length;
    if (n < 8) return ring;
    const sd = sigma; // in samples, since spacing is one unit
    const half = Math.min(Math.ceil(3 * sd), Math.floor((n - 1) / 2));
    const w = Array.from({ length: 2 * half + 1 }, (_, k) => Math.exp(-((k - half) ** 2) / (2 * sd * sd)));
    const wsum = w.reduce((x, y) => x + y, 0);
    return pts.map((_, i) => {
      let x = 0;
      let y = 0;
      for (let k = -half; k <= half; k++) {
        const q = pts[(i + k + n) % n];
        x += q[0] * w[k + half];
        y += q[1] * w[k + half];
      }
      return { X: Math.round(x / wsum), Y: Math.round(y / wsum) };
    });
  });
  return union(out);
};

const dropSmall = (paths, minArea) => paths.filter((p) => Math.abs(Clipper.Area(p)) >= minArea * S * S);

const circle = (cx, cy, r, n = 96) => [
  Array.from({ length: n }, (_, i) => ({
    X: Math.round((cx + r * Math.cos((2 * Math.PI * i) / n)) * S),
    Y: Math.round((cy + r * Math.sin((2 * Math.PI * i) / n)) * S),
  })),
];

// Douglas-Peucker on a closed ring: split at the point farthest from the
// first, simplify both open chains, rejoin.
const simplifyChain = (pts, t2) => {
  const keep = new Uint8Array(pts.length);
  keep[0] = keep[pts.length - 1] = 1;
  const stack = [[0, pts.length - 1]];
  while (stack.length) {
    const [i, j] = stack.pop();
    const a = pts[i];
    const b = pts[j];
    const dx = b.X - a.X;
    const dy = b.Y - a.Y;
    const l2 = dx * dx + dy * dy;
    let m = -1;
    let md = t2;
    for (let k = i + 1; k < j; k++) {
      const p = pts[k];
      const t = l2 ? Math.max(0, Math.min(1, ((p.X - a.X) * dx + (p.Y - a.Y) * dy) / l2)) : 0;
      const d = (a.X + t * dx - p.X) ** 2 + (a.Y + t * dy - p.Y) ** 2;
      if (d > md) {
        md = d;
        m = k;
      }
    }
    if (m > 0) {
      keep[m] = 1;
      stack.push([i, m], [m, j]);
    }
  }
  return pts.filter((_, i) => keep[i]);
};

const simplify = (ring, tol) => {
  let far = 0;
  let fd = -1;
  for (let k = 1; k < ring.length; k++) {
    const d = (ring[k].X - ring[0].X) ** 2 + (ring[k].Y - ring[0].Y) ** 2;
    if (d > fd) {
      fd = d;
      far = k;
    }
  }
  const t2 = (tol * S) ** 2;
  const a = simplifyChain(ring.slice(0, far + 1), t2);
  const b = simplifyChain([...ring.slice(far), ring[0]], t2);
  return [...a.slice(0, -1), ...b.slice(0, -1)];
};

// Closed quadratic B-spline through edge midpoints: tangent-continuous,
// never overshoots, one q command per simplified vertex. Coordinates are
// rounded to whole units (a quarter pixel at 128px) and written relative,
// which roughly halves the path data.
const toPathData = (paths, tol) =>
  paths
    .map((p) => simplify(p, tol))
    .filter((p) => p.length >= 3)
    .map((p) => {
      const r = (v) => Math.round(v / S);
      const pts = [];
      p.forEach((v, i) => {
        const w = p[(i + 1) % p.length];
        pts.push([r(v.X), r(v.Y)], [r((v.X + w.X) / 2), r((v.Y + w.Y) / 2)]);
      });
      let [x, y] = pts[pts.length - 1];
      const nums = [];
      for (let i = 0; i < pts.length; i += 2) {
        const [cx, cy] = pts[i];
        const [ex, ey] = pts[i + 1];
        nums.push(cx - x, cy - y, ex - x, ey - y);
        [x, y] = [ex, ey];
      }
      const [sx, sy] = pts[pts.length - 1];
      return `M${sx} ${sy}q${nums.join(' ').replace(/ -/g, '-')}z`;
    })
    .join('');

/**
 * Build one globe icon. Returns <path> element strings for a 512x512 viewBox:
 * the disc with all land cut out, plus a dimmed non-focus land layer when
 * `focus` is given.
 */
export function makeGlobe({
  center,
  zoom = 1,
  smooth = 7,
  open,
  grow = 0,
  minArea = 300,
  focus = [],
  dim = 0.5,
  tolerance = 1.5,
  pin = 0,
  pinGap = 0,
}) {
  const projection = geoOrthographic()
    .rotate([-center[0], -center[1]])
    .scale(INNER_R * zoom)
    .translate([256, 256])
    .clipAngle((Math.asin(Math.min(1, 1 / zoom)) * 180) / Math.PI)
    .precision(0.1);

  const project = (geo) => {
    const rings = [];
    let ring;
    const pt = (x, y) => ({ X: Math.round(x * S), Y: Math.round(y * S) });
    geoPath(projection, {
      moveTo: (x, y) => rings.push((ring = [pt(x, y)])),
      lineTo: (x, y) => ring.push(pt(x, y)),
      closePath: () => {},
      arc: () => {},
    })(geo);
    // Pre-simplifying to 0.3 units is invisible and makes the offsets an
    // order of magnitude cheaper on 1:50m coastlines.
    const cleaned = rings.map((r) => simplify(r, 0.3)).filter((r) => r.length >= 3);
    return union(cleaned, PolyFillType.pftEvenOdd);
  };

  // grow first, so narrow countries are fattened before smoothing can pinch their necks
  const shape = (geo) => dropSmall(gauss(morph(offset(project(geo), grow), open ?? smooth * 0.6), smooth), minArea);
  const landPath = (land) => `<path fill="currentColor" fill-rule="evenodd" d="${DISC}${toPathData(land, tolerance)}"/>`;

  let land = shape(LAND);
  if (!focus.length) return [landPath(land)];

  const geo = countries(focus);
  let region = intersect(land, shape(geo));

  if (pin) {
    const [px, py] = projection(geoCentroid(geo));
    land = union([...subtract(land, circle(px, py, pin + pinGap)), ...circle(px, py, pin)]);
    region = circle(px, py, pin);
  }

  // Non-focus land, less a hair of the focus region (removes numerical
  // slivers where both coastlines coincide), then grown 3 units out into the
  // ocean: dim currentColor over solid currentColor is invisible, and the
  // overlap means its separately fitted coastline can never leave a seam.
  const other = dropSmall(subtract(land, offset(region, 0.5)), minArea / 4);
  const dimmed = subtract(offset(other, 3), region);

  const paths = [landPath(land)];
  if (dimmed.length) {
    paths.push(`<path fill="currentColor" fill-opacity="${dim}" fill-rule="evenodd" d="${toPathData(dimmed, tolerance)}"/>`);
  }
  return paths;
}

export const standaloneSvg = (paths) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">${paths.join('')}</svg>\n`;
