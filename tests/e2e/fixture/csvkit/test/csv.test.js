const test = require("node:test");
const assert = require("node:assert");
const { toCsv } = require("../src/csv");

test("plain values are joined with commas", () => {
  assert.strictEqual(toCsv([["a", "b"], [1, 2]]), "a,b\n1,2");
});
