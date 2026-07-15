import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import assert from "node:assert/strict";

import {
  appendDrawingPoint,
  buildRoundedDrawingPath,
  createDrawingPath,
  prepareArcLengthPath,
  renderSvg,
  sampleAt,
  type Point,
} from "./brush.ts";

const INFINITY_POINTS: Point[] = [
  { x: 500, y: 520 }, { x: 450, y: 450 }, { x: 390, y: 395 },
  { x: 320, y: 370 }, { x: 250, y: 370 }, { x: 180, y: 390 },
  { x: 130, y: 450 }, { x: 120, y: 520 }, { x: 155, y: 585 },
  { x: 220, y: 635 }, { x: 300, y: 650 }, { x: 380, y: 620 },
  { x: 440, y: 570 }, { x: 500, y: 520 }, { x: 560, y: 465 },
  { x: 620, y: 410 }, { x: 700, y: 370 }, { x: 770, y: 380 },
  { x: 830, y: 420 }, { x: 870, y: 480 }, { x: 875, y: 545 },
  { x: 845, y: 610 }, { x: 790, y: 660 }, { x: 720, y: 675 },
  { x: 650, y: 655 }, { x: 585, y: 610 }, { x: 540, y: 560 },
  { x: 500, y: 520 },
];

function selfCheck(): void {
  assert.equal(
    buildRoundedDrawingPath(
      [{ x: 0, y: 0 }, { x: 100, y: 0 }, { x: 100, y: 100 }],
      40
    ),
    "M 0 0 L 55 0 Q 100 0 100 45 L 100 100"
  );
  const started = createDrawingPath({ x: 0, y: 0 }, 40);
  const straight = appendDrawingPoint(
    appendDrawingPoint(started, { x: 20, y: 0 }),
    { x: 70, y: 0 }
  );
  assert.equal(straight.points.length, 2);
  assert.equal(appendDrawingPoint(started, { x: 1, y: 1 }), started);
  const horizontal = prepareArcLengthPath([{ x: 0, y: 0 }, { x: 100, y: 0 }]);
  const vertical = prepareArcLengthPath([{ x: 0, y: 0 }, { x: 0, y: 100 }]);
  assert.equal(sampleAt(horizontal, 0.5).angle, 0);
  assert.ok(Math.abs(sampleAt(vertical, 0.5).angle - Math.PI / 2) < 1e-12);
  assert.equal(sampleAt(horizontal, 2).progress, 1);
}

selfCheck();
const input = process.argv[2] ?? "assets/example.webp";
const output = process.argv[3] ?? "generated/typescript.svg";
mkdirSync(output.slice(0, Math.max(0, output.lastIndexOf("/"))) || ".", {
  recursive: true,
});
const svg = renderSvg(
  readFileSync(input),
  "image/webp",
  1000,
  1000,
  INFINITY_POINTS,
  "🤝 best friends forever",
  { fontSize: 40, magicGradient: true, shadow: true }
);
assert.match(svg, /data:image\/webp;base64,/);
assert.match(svg, /🤝 best friends forever/);
writeFileSync(output, svg, "utf8");
console.log(`Wrote ${output}`);
