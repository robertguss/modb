# What does porting Mo's bytecode loader and verifier to Rust cost?

Type: prototype
Status: open

## Question

Port `src/bytecode` in `~/code/mo` (the loader and verifier, about 8,100 non-blank lines of C, the part that reads untrusted bytes) to Rust behind its existing C header, as a throwaway that is never merged into Mo. Run Mo's existing unit tests, fuzz corpus and golden corpus against it.

Record what it cost and what it showed:

- lines of Rust, and lines inside `unsafe`;
- what the boundary with the remaining C forced (shared types, the `prims.def` table, error handling);
- agent time and tokens spent;
- speed against the C version;
- which of the module's CBMC proofs have an equivalent in Kani, Rust's model checker;
- every difference in behaviour the tests found.

The decision that waits on it: whether a module-by-module move is practical, or whether a hybrid of two languages costs more than it saves.
