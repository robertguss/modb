## What a program does today: one whole Map for each kept version. Every put
## keeps the version before it.
module WholeMaps

row = "0123456789012345678901234567890123456789012345678901234567890123"

struct Rows
  kept: List(Map(Int, Text))
  newest: Map(Int, Text)
end

service
  state Rows = Rows(kept: [], newest: {})
  tools grow, put, get, old
  token from env "PERF_TOKEN"
end

## Adds `step` rows to the newest version and keeps no version.
fn grow(state: Rows, _now: Time, step: Int) : (Rows, Int)
  var newest = state.newest
  first = newest.size
  for key in first..(first + step)
    newest = newest.set(key, row)
  end
  (Rows(kept: state.kept, newest: newest), newest.size)
end

## Keeps the version as it is, then sets one row. Gives the number of kept versions.
fn put(state: Rows, _now: Time, key: Int, value: Text) : (Rows, Int)
  kept = state.kept.append(state.newest)
  (Rows(kept: kept, newest: state.newest.set(key, value)), kept.size)
end

## Reads one row of the newest version.
fn get(state: Rows, _now: Time, key: Int) : Text
  state.newest.get(key) or ""
end

## Reads one row of a kept version, oldest first.
fn old(state: Rows, _now: Time, version: Int, key: Int) : Text
  (state.kept.get(version) or {}).get(key) or ""
end
