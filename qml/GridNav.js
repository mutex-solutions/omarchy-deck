.pragma library

// Spatial navigation over Deck's actual cell rectangles. The focused identity is
// a section id, not an index: dragging and resizing can reorder the model without
// moving the cursor to an unrelated control.
function next(placements, currentId, dx, dy) {
  var list = placements || []
  if (list.length === 0) return ""
  var current = null
  for (var i = 0; i < list.length; i++)
    if (String(list[i].id) === String(currentId)) current = list[i]
  if (!current) return String(list[0].id)
  if (dx === 0 && dy === 0) return String(current.id)

  var cx = current.col + current.span / 2
  var cy = current.row + current.rows / 2
  var best = null
  var bestScore = Infinity
  for (var j = 0; j < list.length; j++) {
    var candidate = list[j]
    if (String(candidate.id) === String(current.id)) continue
    var x = candidate.col + candidate.span / 2
    var y = candidate.row + candidate.rows / 2
    var forward = dx !== 0 ? (x - cx) * dx : (y - cy) * dy
    if (forward <= 0) continue

    // Prefer a tile whose row/column overlaps ours. If there is none, the
    // nearest diagonal is still a better answer than a list-order jump.
    var overlap = dx !== 0
      ? Math.min(current.row + current.rows, candidate.row + candidate.rows) - Math.max(current.row, candidate.row)
      : Math.min(current.col + current.span, candidate.col + candidate.span) - Math.max(current.col, candidate.col)
    var aligned = overlap > 0
    var sideways = Math.abs(dx !== 0 ? y - cy : x - cx)
    var score = forward * 100 + sideways * (aligned ? 10 : 80) + (aligned ? 0 : 1000)
    if (score < bestScore) {
      best = candidate
      bestScore = score
    }
  }
  return best ? String(best.id) : String(current.id)
}
