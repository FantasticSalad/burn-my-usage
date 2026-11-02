// Turns rows (arrays of values) into CSV text.
function toCsv(rows) {
  return rows.map((row) => row.map((v) => String(v)).join(",")).join("\n");
}

module.exports = { toCsv };
