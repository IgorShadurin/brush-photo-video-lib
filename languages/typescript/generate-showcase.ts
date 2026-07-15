import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";

import { renderSvg, type Point, type RenderOptions } from "./brush.ts";

const HEART_POINTS: Point[] = [
  { x: 500, y: 720 },
  { x: 420, y: 640 },
  { x: 340, y: 560 },
  { x: 290, y: 470 },
  { x: 280, y: 390 },
  { x: 300, y: 330 },
  { x: 350, y: 290 },
  { x: 410, y: 285 },
  { x: 460, y: 310 },
  { x: 500, y: 360 },
  { x: 540, y: 310 },
  { x: 590, y: 285 },
  { x: 650, y: 290 },
  { x: 700, y: 330 },
  { x: 720, y: 390 },
  { x: 710, y: 470 },
  { x: 660, y: 560 },
  { x: 580, y: 640 },
  { x: 500, y: 720 },
];

const STAR_POINTS: Point[] = [
  { x: 500, y: 75 },
  { x: 550, y: 201 },
  { x: 690, y: 208 },
  { x: 581, y: 296 },
  { x: 618, y: 432 },
  { x: 500, y: 355 },
  { x: 382, y: 432 },
  { x: 419, y: 296 },
  { x: 310, y: 208 },
  { x: 450, y: 201 },
  { x: 500, y: 75 },
];

const image = readFileSync("assets/example.webp");
const common: RenderOptions = {
  fontFamily: "Arial Rounded MT Bold, Arial, sans-serif",
  fontWeight: 800,
  letterSpacing: 1.5,
  repeatText: false,
};

const repeated = (word: string, count: number): string =>
  Array.from({ length: count }, () => word).join("   ");

const hello = renderSvg(
  image,
  "image/webp",
  1000,
  1000,
  HEART_POINTS,
  repeated("Hello", 12),
  {
    ...common,
    fontSize: 44,
    color: "#ffffff",
    strokeColor: "rgba(15,23,42,0.9)",
    strokeWidth: 1.75,
    shadow: true,
  }
);

const world = renderSvg(
  image,
  "image/webp",
  1000,
  1000,
  STAR_POINTS,
  repeated("World", 10),
  {
    ...common,
    fontSize: 40,
    color: "#000000",
    strokeColor: "rgba(255,255,255,0.8)",
    strokeWidth: 1.75,
    shadow: false,
  }
);

assert.ok((hello.match(/Hello/g) ?? []).length > 1);
assert.ok((world.match(/World/g) ?? []).length > 1);
writeFileSync("assets/example-hello-white.svg", hello, "utf8");
writeFileSync("assets/example-world-black.svg", world, "utf8");
console.log("Wrote the Hello heart and World star showcase SVGs");
