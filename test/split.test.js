import { test } from "node:test";
import assert from "node:assert/strict";
import { split, formatDollars } from "../src/split.js";

test("splits an even amount equally", () => {
  assert.deepEqual(split(90, 3), [30, 30, 30]);
});

test("splits between two people", () => {
  assert.deepEqual(split(25.5, 2), [12.75, 12.75]);
});

test("distributes remainder cents", () => {
  const shares = split(100, 3);
  const totalCents = shares.reduce((sum, share) => sum + Math.round(share * 100), 0);

  assert.deepEqual(shares, [33.34, 33.33, 33.33]);
  assert.equal(totalCents, 10000);
});

test("one person pays the whole bill", () => {
  assert.deepEqual(split(42.42, 1), [42.42]);
});

test("rejects a negative amount", () => {
  assert.throws(() => split(-5, 2), RangeError);
});

test("rejects a non-integer number of people", () => {
  assert.throws(() => split(10, 2.5), RangeError);
  assert.throws(() => split(10, 0), RangeError);
});

test("formats dollars with two decimals", () => {
  assert.equal(formatDollars(12.5), "$12.50");
});
