## Error types for the MoDB storage engine.
module Modb.Errors
expose ModbError(..), to_text, wrap_io

## Every failure returned by MoDB operations.
enum ModbError
  Io(FileError)
  Corrupt(reason: Text)
  KeyTooLarge(size: Int, max: Int)
  InvalidArgument(reason: Text)
  SnapshotUnknown(id: Int)
  TxAborted(reason: Text)
end

## Formats a `ModbError` as a readable diagnostic.
fn to_text(err: ModbError) : Text
  case err
    Io(file_err): "io error: #{file_err.to_text}"
    Corrupt(reason: r): "corrupt database: #{r}"
    KeyTooLarge(size: s, max: m): "key too large: #{s} bytes (max #{m})"
    InvalidArgument(reason: r): "invalid argument: #{r}"
    SnapshotUnknown(id: id): "unknown snapshot id #{id}"
    TxAborted(reason: r): "transaction aborted: #{r}"
  end
end

## Lifts a `FileError` result into `ModbError`.
fn wrap_io(res: Result(T, FileError)) : Result(T, ModbError)
  case res
    Ok(v): Ok(v)
    Error(e): Error(Io(e))
  end
end

test "error formatting covers every variant"
  assert Io(NotFound(path: "a.db")).to_text == "io error: a.db: no such file"
  assert Corrupt(reason: "bad checksum").to_text == "corrupt database: bad checksum"
  assert KeyTooLarge(size: 600, max: 512).to_text == "key too large: 600 bytes (max 512)"
  assert InvalidArgument(reason: "empty").to_text == "invalid argument: empty"
  assert SnapshotUnknown(id: 7).to_text == "unknown snapshot id 7"
  assert TxAborted(reason: "cancel").to_text == "transaction aborted: cancel"
end
