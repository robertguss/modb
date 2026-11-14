# What does a safe-Rust slice of Mo's heap and VM cost?

Type: prototype
Status: closed

## Question

Build a small Rust version of the part of Mo's runtime where ownership is hardest, as a throwaway that is never merged into Mo: values with more than one holder, dropping them, resetting and reusing an allocation in place, and a VM stack that moves when it grows (`src/heap/cell.c`, `heap.c` and `reuse.c`, `src/vm/process.c` and `execute.c` in `~/code/mo`). The interior is safe Rust. Every `unsafe` block and every boundary with C states the rule it relies on. Run the same programs through it and through the C and compare the results.

Record what it cost and what it showed:

- lines of Rust, lines inside `unsafe`, and what each `unsafe` block is for;
- which C representations had to change (pointers kept as bytes in 16-byte cells, holders counted by hand, allocations linked through their own headers, frames in a byte buffer that can move) and what replaced each;
- memory use and speed against the C version;
- agent time and tokens spent;
- every difference in behaviour found.

The decision that waits on it: whether the runtime can be mostly safe Rust, or whether a port would carry the same risks inside `unsafe`.

The loader and verifier are not the slice because they read bytes and own little; porting them would not test ownership.

## Comments

2026-11-14: whether this prototype is worth running is disputed. One outside review asked for this heap-and-VM slice. A second said to skip it: Mo's values are immutable and never form cycles, which safe Rust already handles, so the slice would show little; the open questions are speed, memory and the cost of the boundary. See the comments on [How does Mo's runtime become memory safe?](24-how-does-mos-runtime-become-memory-safe.md).

**2026-11-14, closed unanswered.** Robert stopped the map before this ticket was answered. See [the map](../map.md).
