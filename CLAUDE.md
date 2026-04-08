# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Z is a pure Crystal implementation of DEFLATE (RFC 1951), zlib (RFC 1950), and gzip (RFC 1952). Zero native dependencies — no libz, no C bindings. The API mirrors Crystal's `Compress::Deflate`, `Compress::Zlib`, and `Compress::Gzip`.

## Commands

```bash
crystal spec                           # Run all tests
crystal spec spec/z/deflate/reader_spec.cr  # Run a single spec file
crystal spec spec/z/deflate/reader_spec.cr:15  # Run a specific test by line

crystal build --release bench/comparison_bench.cr -o bench/comparison_bench
./bench/comparison_bench               # Z vs stdlib (libz) performance comparison

bash bench/run_all.sh                  # Run all benchmarks
```

## Architecture

### Layered IO Wrapper Pattern

Format wrappers compose on top of raw DEFLATE, each adding header/trailer/checksum:

```
Gzip::Reader/Writer  →  Deflate::Reader/Writer  →  Inflater / (LZ77 + BlockWriter)
Zlib::Reader/Writer  →  Deflate::Reader/Writer  →  Inflater / (LZ77 + BlockWriter)
```

All Reader/Writer classes extend `IO` with `IO::Buffered` and support the `.open(io) { |rw| ... }` block pattern matching stdlib conventions.

### Decompression Path

`Inflater` (`deflate/inflate.cr`) is a state machine: `BlockHeader → StoredBlockInit/DecodeSymbols → Finished`. It uses a unified 64KB flat buffer as both output accumulator and sliding window — back-references read directly from this buffer, eliminating separate window copies.

`Huffman::Tree` (`huffman/tree.cr`) is a two-level lookup table: 11-bit primary table (2048 entries) with secondary tables for codes longer than 11 bits. Entry format packs symbol + code length + redirect flag into a `UInt32`.

`BitReader` (`bits/bit_reader.cr`) maintains an 8KB input buffer refilled in bulk from IO, with a 64-bit bit accumulator. The fast path loads 8 bytes at once via pointer cast. After deflate finishes, format wrappers read trailer bytes through `read_trailer_byte` which drains the buffered stream.

### Compression Path

`LZ77` (`deflate/lz77.cr`) finds matches using hash chains (15-bit hash, 32K positions). Compression levels 0-9 configure chain depth, lazy matching (level >= 4), and nice/good length thresholds.

`BlockWriter` (`deflate/block_writer.cr`) accumulates tokens (up to 16384 per block), estimates encoded sizes for stored vs fixed vs dynamic Huffman, and picks the smallest.

`Huffman::Encoder` (`huffman/encoder.cr`) builds optimal trees from frequencies, limits code lengths, and generates canonical codes.

`BitWriter` (`bits/bit_writer.cr`) buffers output in a 4KB buffer, flushing in bulk to IO.

### Checksums

- `CRC32` uses slicing-by-4 (4 table lookups per 4-byte chunk)
- `Adler32` uses NMAX=5552 deferred-modulo batching

Both are computed inline during streaming — no separate pass.

## Commit Style

Do not include a `Co-Authored-By` line in commit messages.
