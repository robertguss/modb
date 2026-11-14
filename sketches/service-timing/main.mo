## A map of numbered rows that can be grown, for timing a service.
module Main

row = "0123456789012345678901234567890123456789012345678901234567890123"

service
  state Map(Int, Text) = {}
  tools grow, put, get
  token from env "PERF_TOKEN"
end

## Adds `step` rows.
fn grow(state: Map(Int, Text), _now: Time, step: Int) : (Map(Int, Text), Int)
  var rows = state
  first = state.size
  for i in first..(first + step)
    rows = rows.set(i, row)
  end
  (rows, rows.size)
end

## Sets one row.
fn put(state: Map(Int, Text), _now: Time, key: Int, value: Text) : (Map(Int, Text), Int)
  rows = state.set(key, value)
  (rows, rows.size)
end

## Reads one row.
fn get(state: Map(Int, Text), _now: Time, key: Int) : Text
  state.get(key) or ""
end
