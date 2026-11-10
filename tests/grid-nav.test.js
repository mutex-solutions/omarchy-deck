const assert = require("assert")
const fs = require("fs"), path = require("path"), vm = require("vm")
const src = fs.readFileSync(path.join(__dirname, "../qml/GridNav.js"), "utf8").replace(/^\.pragma library\n/, "")
const Nav = {}; vm.runInNewContext(src, Nav)

const grid = [
  { id: "a", col: 0, row: 0, span: 2, rows: 1 },
  { id: "b", col: 2, row: 0, span: 1, rows: 1 },
  { id: "c", col: 3, row: 0, span: 1, rows: 1 },
  { id: "d", col: 0, row: 1, span: 2, rows: 1 },
  { id: "e", col: 2, row: 1, span: 2, rows: 1 },
  { id: "f", col: 0, row: 2, span: 4, rows: 1 },
]
let count = 0
function t(name, fn) { fn(); count++ }

t("moves across mixed widths without using model order", () => {
  assert.equal(Nav.next(grid, "a", 1, 0), "b")
  assert.equal(Nav.next(grid, "b", 1, 0), "c")
  assert.equal(Nav.next(grid, "c", -1, 0), "b")
})
t("moves vertically by actual rows and alignment", () => {
  assert.equal(Nav.next(grid, "a", 0, 1), "d")
  assert.equal(Nav.next(grid, "d", 0, -1), "a")
  assert.equal(Nav.next(grid, "d", 1, 0), "e")
  assert.equal(Nav.next(grid, "b", 0, 1), "e")
  assert.equal(Nav.next(grid, "f", 0, -1), "d")
})
t("edges stay put and missing identities start at the first tile", () => {
  assert.equal(Nav.next(grid, "c", 1, 0), "c")
  assert.equal(Nav.next(grid, "a", 0, -1), "a")
  assert.equal(Nav.next(grid, "gone", 1, 0), "a")
  assert.equal(Nav.next([], "gone", 1, 0), "")
})
t("a reordered model keeps the same spatial answer", () => {
  const moved = [grid[5], grid[3], grid[0], grid[4], grid[2], grid[1]]
  assert.equal(Nav.next(moved, "a", 1, 0), "b")
})
console.log("grid navigation ok: " + count + " tests")
