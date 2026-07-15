export interface Point {
  x: number;
  y: number;
}

export interface PathData {
  points: Point[];
  d: string;
  fontSize: number;
}

export interface PathSample extends Point {
  angle: number;
  progress: number;
}

export interface PreparedPath {
  points: Point[];
  segments: Array<{
    start: Point;
    end: Point;
    startDistance: number;
    length: number;
  }>;
  totalLength: number;
}

export interface RenderOptions {
  fontSize?: number;
  fontFamily?: string;
  fontWeight?: number | string;
  letterSpacing?: number;
  color?: string;
  magicGradient?: boolean;
  opacity?: number;
  strokeColor?: string;
  strokeWidth?: number;
  shadow?: boolean;
  repeatText?: boolean;
  revealProgress?: number;
}

export const MIN_DRAWING_POINT_DISTANCE = 3;
export const STRAIGHT_DIRECTION_TOLERANCE_DEGREES = 18;

const MAGIC_STOPS = [
  ["0%", "#ec4899"],
  ["20%", "#f97316"],
  ["40%", "#facc15"],
  ["60%", "#10b981"],
  ["80%", "#3b82f6"],
  ["100%", "#8b5cf6"],
] as const;

function finitePoint(point: Point): boolean {
  return Number.isFinite(point.x) && Number.isFinite(point.y);
}

function clamp(value: number, lower: number, upper: number): number {
  if (!Number.isFinite(value)) return lower;
  return Math.min(upper, Math.max(lower, value));
}

function distance(first: Point, second: Point): number {
  return Math.hypot(second.x - first.x, second.y - first.y);
}

function pointAlong(from: Point, toward: Point, travel: number): Point {
  const total = distance(from, toward);
  if (total === 0) return from;
  const progress = Math.min(1, travel / total);
  return {
    x: from.x + (toward.x - from.x) * progress,
    y: from.y + (toward.y - from.y) * progress,
  };
}

function directionChange(first: Point, corner: Point, next: Point): number {
  const incoming = { x: corner.x - first.x, y: corner.y - first.y };
  const outgoing = { x: next.x - corner.x, y: next.y - corner.y };
  const incomingLength = Math.hypot(incoming.x, incoming.y);
  const outgoingLength = Math.hypot(outgoing.x, outgoing.y);
  if (incomingLength === 0 || outgoingLength === 0) return 0;
  const cosine = clamp(
    (incoming.x * outgoing.x + incoming.y * outgoing.y) /
      (incomingLength * outgoingLength),
    -1,
    1
  );
  return (Math.acos(cosine) * 180) / Math.PI;
}

function formatNumber(value: number): string {
  const rounded = Number(value.toFixed(2));
  return Object.is(rounded, -0) ? "0" : rounded.toString();
}

function formatPoint(point: Point): string {
  return `${formatNumber(point.x)} ${formatNumber(point.y)}`;
}

/** Converts retained pointer anchors into a font-size-aware rounded SVG path. */
export function buildRoundedDrawingPath(
  points: Point[],
  fontSize: number
): string {
  const valid = points.filter(finitePoint);
  const first = valid[0];
  if (!first) return "";
  if (valid.length === 1) return `M ${formatPoint(first)}`;

  const commands = [`M ${formatPoint(first)}`];
  const preferredRadius = Math.max(12, fontSize * 1.25);
  for (let index = 1; index < valid.length - 1; index += 1) {
    const previous = valid[index - 1];
    const corner = valid[index];
    const next = valid[index + 1];
    const trim = Math.min(
      preferredRadius,
      distance(previous, corner) * 0.45,
      distance(corner, next) * 0.45
    );
    const entry = pointAlong(corner, previous, trim);
    const exit = pointAlong(corner, next, trim);
    commands.push(
      `L ${formatPoint(entry)} Q ${formatPoint(corner)} ${formatPoint(exit)}`
    );
  }
  commands.push(`L ${formatPoint(valid[valid.length - 1])}`);
  return commands.join(" ");
}

export function createDrawingPath(point: Point, fontSize = 40): PathData {
  if (!finitePoint(point)) return { points: [], d: "", fontSize };
  return { points: [point], d: `M ${formatPoint(point)}`, fontSize };
}

/** Ignores jitter and replaces the pending endpoint while movement stays straight. */
export function appendDrawingPoint(path: PathData, point: Point): PathData {
  if (!finitePoint(point)) return path;
  const points = path.points;
  const last = points[points.length - 1];
  if (!last || distance(last, point) < MIN_DRAWING_POINT_DISTANCE) return path;

  let nextPoints: Point[];
  if (points.length === 1) {
    nextPoints = [...points, point];
  } else {
    const previous = points[points.length - 2];
    nextPoints =
      directionChange(previous, last, point) <
      STRAIGHT_DIRECTION_TOLERANCE_DEGREES
        ? [...points.slice(0, -1), point]
        : [...points, point];
  }
  return {
    points: nextPoints,
    fontSize: path.fontSize,
    d: buildRoundedDrawingPath(nextPoints, path.fontSize),
  };
}

export function finishDrawingPath(path: PathData): PathData | null {
  return path.points.length >= 2 ? path : null;
}

export function drawingPathFromPoints(
  points: Point[],
  fontSize = 40
): PathData | null {
  const first = points.find(finitePoint);
  if (!first) return null;
  let path = createDrawingPath(first, fontSize);
  let seenFirst = false;
  for (const point of points) {
    if (!finitePoint(point)) continue;
    if (!seenFirst && point === first) {
      seenFirst = true;
      continue;
    }
    path = appendDrawingPoint(path, point);
  }
  return finishDrawingPath(path);
}

function perpendicularDistance(point: Point, start: Point, end: Point): number {
  const dx = end.x - start.x;
  const dy = end.y - start.y;
  const squaredLength = dx * dx + dy * dy;
  if (squaredLength === 0) return distance(start, point);
  const projection = clamp(
    ((point.x - start.x) * dx + (point.y - start.y) * dy) / squaredLength,
    0,
    1
  );
  return distance(point, {
    x: start.x + projection * dx,
    y: start.y + projection * dy,
  });
}

function simplify(points: Point[], tolerance: number): Point[] {
  if (points.length <= 2 || tolerance <= 0) return points;
  const retained = new Array(points.length).fill(false);
  retained[0] = true;
  retained[points.length - 1] = true;
  const ranges: Array<[number, number]> = [[0, points.length - 1]];
  while (ranges.length > 0) {
    const [first, last] = ranges.pop()!;
    if (last <= first + 1) continue;
    let greatestDistance = 0;
    let greatestIndex = -1;
    for (let index = first + 1; index < last; index += 1) {
      const candidate = perpendicularDistance(
        points[index],
        points[first],
        points[last]
      );
      if (candidate > greatestDistance) {
        greatestDistance = candidate;
        greatestIndex = index;
      }
    }
    if (greatestDistance > tolerance && greatestIndex >= 0) {
      retained[greatestIndex] = true;
      ranges.push([first, greatestIndex], [greatestIndex, last]);
    }
  }
  return points.filter((_, index) => retained[index]);
}

/** Builds the Swift-style simplified cumulative arc-length representation. */
export function prepareArcLengthPath(
  input: Point[],
  minimumPointDistance = 0.5
): PreparedPath {
  const threshold = Number.isFinite(minimumPointDistance)
    ? Math.max(0, minimumPointDistance)
    : 0.5;
  const valid = input.filter(finitePoint);
  const filtered: Point[] = [];
  for (const point of valid) {
    if (
      filtered.length === 0 ||
      distance(filtered[filtered.length - 1], point) >= threshold
    ) {
      filtered.push(point);
    }
  }
  const last = valid[valid.length - 1];
  if (
    last &&
    filtered.length > 0 &&
    distance(filtered[filtered.length - 1], last) > 0
  ) {
    filtered.push(last);
  }
  const points = simplify(filtered, Math.max(threshold * 0.5, 0.1));
  const segments: PreparedPath["segments"] = [];
  let totalLength = 0;
  for (let index = 1; index < points.length; index += 1) {
    const length = distance(points[index - 1], points[index]);
    if (!(length > 0) || !Number.isFinite(length)) continue;
    segments.push({
      start: points[index - 1],
      end: points[index],
      startDistance: totalLength,
      length,
    });
    totalLength += length;
  }
  return { points, segments, totalLength };
}

function pointAtDistance(path: PreparedPath, requestedDistance: number): Point {
  if (path.segments.length === 0) return { x: 0, y: 0 };
  const distanceOnPath = clamp(requestedDistance, 0, path.totalLength);
  if (distanceOnPath <= 0) return path.segments[0].start;
  if (distanceOnPath >= path.totalLength)
    return path.segments[path.segments.length - 1].end;
  let lower = 0;
  let upper = path.segments.length - 1;
  while (lower < upper) {
    const middle = Math.floor((lower + upper) / 2);
    const segment = path.segments[middle];
    if (distanceOnPath > segment.startDistance + segment.length) {
      lower = middle + 1;
    } else {
      upper = middle;
    }
  }
  const segment = path.segments[lower];
  const fraction = clamp(
    (distanceOnPath - segment.startDistance) / segment.length,
    0,
    1
  );
  return {
    x: segment.start.x + (segment.end.x - segment.start.x) * fraction,
    y: segment.start.y + (segment.end.y - segment.start.y) * fraction,
  };
}

/** Samples a stable position and secant tangent for animation or per-frame layout. */
export function sampleAt(
  path: PreparedPath,
  progress: number,
  fontSize = 40
): PathSample {
  const boundedProgress = clamp(progress, 0, 1);
  if (!(path.totalLength > 0)) {
    return { x: 0, y: 0, angle: 0, progress: boundedProgress };
  }
  const target = path.totalLength * boundedProgress;
  const preferred = Math.max(fontSize * 1.1, 0.75);
  const tangentSample = Math.max(
    Math.min(preferred, path.totalLength * 0.06),
    0.75
  );
  const before = pointAtDistance(path, target - tangentSample);
  const after = pointAtDistance(path, target + tangentSample);
  const point = pointAtDistance(path, target);
  return {
    ...point,
    angle: Math.atan2(after.y - before.y, after.x - before.x),
    progress: boundedProgress,
  };
}

export function getStableRepeatedText(text: string, fontSize: number): string {
  const phrase = text.trim();
  if (!phrase) return "";
  const estimatedWidth = Math.max(
    fontSize,
    Math.max(1, Array.from(phrase).length) * fontSize * 0.62
  );
  const repetitions = Math.min(
    256,
    Math.max(16, Math.ceil(20_000 / estimatedWidth))
  );
  return Array(repetitions).fill(phrase).join("   ");
}

function xmlEscape(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function base64(bytes: Uint8Array): string {
  const alphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  let result = "";
  for (let index = 0; index < bytes.length; index += 3) {
    const a = bytes[index];
    const b = index + 1 < bytes.length ? bytes[index + 1] : 0;
    const c = index + 2 < bytes.length ? bytes[index + 2] : 0;
    const triple = (a << 16) | (b << 8) | c;
    result += alphabet[(triple >> 18) & 63];
    result += alphabet[(triple >> 12) & 63];
    result += index + 1 < bytes.length ? alphabet[(triple >> 6) & 63] : "=";
    result += index + 2 < bytes.length ? alphabet[triple & 63] : "=";
  }
  return result;
}

/** Renders a standalone SVG containing both the raster photo and curved text. */
export function renderSvg(
  imageBytes: Uint8Array,
  mimeType: string,
  width: number,
  height: number,
  points: Point[],
  text: string,
  options: RenderOptions = {}
): string {
  const allowedMimeTypes = new Set([
    "image/png",
    "image/jpeg",
    "image/webp",
    "image/gif",
    "image/avif",
  ]);
  if (!allowedMimeTypes.has(mimeType)) throw new Error("Unsupported image MIME type");
  if (!(width > 0) || !(height > 0) || !Number.isFinite(width + height)) {
    throw new Error("Image dimensions must be finite and positive");
  }
  const phrase = text.trim();
  if (!phrase) throw new Error("Text must not be empty");

  const fontSize =
    Number.isFinite(options.fontSize) && (options.fontSize ?? 0) > 0
      ? options.fontSize!
      : 40;
  const path = drawingPathFromPoints(points, fontSize);
  if (!path) throw new Error("At least two usable points are required");
  const family = options.fontFamily ?? "Arial, sans-serif";
  const weight = options.fontWeight ?? 700;
  const letterSpacing =
    Number.isFinite(options.letterSpacing) && (options.letterSpacing ?? -1) >= 0
      ? options.letterSpacing!
      : Math.max(0.75, fontSize * 0.06);
  const opacity = clamp(options.opacity ?? 1, 0, 1);
  const reveal = clamp(options.revealProgress ?? 1, 0, 1);
  const strokeWidth = Math.max(0, options.strokeWidth ?? 1.5);
  const repeated = options.repeatText === false
    ? phrase
    : getStableRepeatedText(phrase, fontSize);
  const fill = options.magicGradient
    ? "url(#brush-gradient)"
    : xmlEscape(options.color ?? "#ffffff");
  const gradient = options.magicGradient
    ? `<linearGradient id="brush-gradient" x1="100" y1="150" x2="900" y2="850" gradientUnits="userSpaceOnUse">${MAGIC_STOPS.map(
        ([offset, color]) =>
          `<stop offset="${offset}" stop-color="${color}"/>`
      ).join("")}</linearGradient>`
    : "";
  const shadow = options.shadow === false
    ? ""
    : '<filter id="brush-shadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="2" stdDeviation="2" flood-color="#0f172a" flood-opacity="0.65"/></filter>';
  const filter = options.shadow === false ? "" : ' filter="url(#brush-shadow)"';

  return `<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${formatNumber(width)}" height="${formatNumber(height)}" viewBox="0 0 ${formatNumber(width)} ${formatNumber(height)}">\n  <image width="${formatNumber(width)}" height="${formatNumber(height)}" preserveAspectRatio="xMidYMid slice" href="data:${mimeType};base64,${base64(imageBytes)}"/>\n  <defs><path id="brush-path" d="${xmlEscape(path.d)}"/>${gradient}${shadow}<mask id="brush-reveal" x="0" y="0" width="${formatNumber(width)}" height="${formatNumber(height)}" maskUnits="userSpaceOnUse"><rect width="100%" height="100%" fill="black"/><path d="${xmlEscape(path.d)}" pathLength="1" fill="none" stroke="white" stroke-width="${formatNumber(fontSize * 2.4)}" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="1" stroke-dashoffset="${formatNumber(1 - reveal)}"/></mask></defs>\n  <g mask="url(#brush-reveal)" opacity="${formatNumber(opacity)}"${filter}><text font-family="${xmlEscape(family)}" font-size="${formatNumber(fontSize)}" font-weight="${xmlEscape(String(weight))}" letter-spacing="${formatNumber(letterSpacing)}" fill="${fill}" stroke="${xmlEscape(options.strokeColor ?? "rgba(15,23,42,0.72)")}" stroke-width="${formatNumber(strokeWidth)}" paint-order="stroke fill"><textPath href="#brush-path" xlink:href="#brush-path" startOffset="0" spacing="exact">${xmlEscape(repeated)}</textPath></text></g>\n</svg>\n`;
}
