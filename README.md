# Z

Pure Crystal implementation of DEFLATE ([RFC 1951](https://datatracker.ietf.org/doc/html/rfc1951)), zlib ([RFC 1950](https://datatracker.ietf.org/doc/html/rfc1950)), and gzip ([RFC 1952](https://datatracker.ietf.org/doc/html/rfc1952)) compression. Zero native dependencies — no libz, no C bindings.

The API mirrors Crystal's `Compress::Deflate`, `Compress::Zlib`, and `Compress::Gzip` so you can swap them in with minimal changes.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  z:
    github: jkthorne/z
```

Then run `shards install`.

## Usage

```crystal
require "z"
```

### Gzip

```crystal
# Compress
compressed = IO::Memory.new
Z::Gzip::Writer.open(compressed) do |gz|
  gz.print "Hello, World!"
end

# Decompress
compressed.rewind
Z::Gzip::Reader.open(compressed) do |gz|
  puts gz.gets_to_end # => "Hello, World!"
end
```

### Zlib

```crystal
compressed = IO::Memory.new
Z::Zlib::Writer.open(compressed) do |zl|
  zl.print "Hello, World!"
end

compressed.rewind
Z::Zlib::Reader.open(compressed) do |zl|
  puts zl.gets_to_end # => "Hello, World!"
end
```

### Raw DEFLATE

```crystal
compressed = IO::Memory.new
Z::Deflate::Writer.open(compressed) do |deflate|
  deflate.print "Hello, World!"
end

compressed.rewind
Z::Deflate::Reader.open(compressed) do |inflate|
  puts inflate.gets_to_end # => "Hello, World!"
end
```

### Compression levels

Pass `level:` to any writer. Levels range from 0 (store, no compression) to 9 (best compression, slowest). The default is 6.

```crystal
# Fast compression
Z::Gzip::Writer.open(io, level: Z::Deflate::BEST_SPEED) { |gz| gz.print data }

# Maximum compression
Z::Gzip::Writer.open(io, level: Z::Deflate::BEST_COMPRESSION) { |gz| gz.print data }

# No compression (stored)
Z::Gzip::Writer.open(io, level: Z::Deflate::NO_COMPRESSION) { |gz| gz.print data }
```

| Constant | Value | Description |
|---|---|---|
| `Z::Deflate::NO_COMPRESSION` | 0 | Store without compressing |
| `Z::Deflate::BEST_SPEED` | 1 | Fastest compression |
| `Z::Deflate::DEFAULT_COMPRESSION` | 6 | Balanced speed/ratio |
| `Z::Deflate::BEST_COMPRESSION` | 9 | Smallest output |

### Gzip header metadata

```crystal
header = Z::Gzip::Header.new
header.name = "data.txt"
header.modification_time = Time.utc

compressed = IO::Memory.new
Z::Gzip::Writer.new(compressed, header: header) do |gz|
  gz.print "file contents"
end
```

When reading, access the header through the reader:

```crystal
Z::Gzip::Reader.open(io) do |gz|
  gz.header.name            # => "data.txt" or nil
  gz.header.modification_time
  gz.header.os
  gz.header.comment         # => String or nil
  gz.gets_to_end
end
```

### Checksums

The checksum modules are available standalone:

```crystal
Z::Adler32.checksum("Hello".to_slice) # => UInt32
Z::CRC32.checksum("Hello".to_slice)   # => UInt32

# Incremental
adler = Z::Adler32.initial
adler = Z::Adler32.update(chunk1, adler)
adler = Z::Adler32.update(chunk2, adler)

crc = Z::CRC32.initial
crc = Z::CRC32.update(chunk1, crc)
crc = Z::CRC32.update(chunk2, crc)
checksum = Z::CRC32.finalize(crc)
```

### Working with files

```crystal
# Compress a file
File.open("data.txt") do |input|
  File.open("data.txt.gz", "w") do |output|
    Z::Gzip::Writer.open(output) do |gz|
      IO.copy(input, gz)
    end
  end
end

# Decompress a file
File.open("data.txt.gz") do |input|
  Z::Gzip::Reader.open(input) do |gz|
    File.open("data.txt", "w") do |output|
      IO.copy(gz, output)
    end
  end
end
```

### Interoperability

Output from Z is valid and can be read by any compliant implementation. These all work:

```crystal
# Compress with Z, decompress with Crystal stdlib
compressed = IO::Memory.new
Z::Gzip::Writer.open(compressed) { |gz| gz.print data }
compressed.rewind
Compress::Gzip::Reader.open(compressed) { |gz| gz.gets_to_end }

# Compress with Crystal stdlib, decompress with Z
compressed = IO::Memory.new
Compress::Gzip::Writer.open(compressed) { |gz| gz.print data }
compressed.rewind
Z::Gzip::Reader.open(compressed) { |gz| gz.gets_to_end }
```

Output is also compatible with command-line tools like `gzip`, `gunzip`, and `zlib-flate`.

## Performance

Z is a pure Crystal implementation competing against Crystal's stdlib which wraps C libz. Benchmarks run on 1 MB of data at the default compression level (6), built with `--release`.

### Compression

| Format | Z (MB/s) | stdlib/libz (MB/s) | Z / stdlib | Ratio |
|---|--:|--:|--:|---|
| Deflate (text) | 140 | 483 | 0.3x | identical |
| Gzip (text) | 135 | 461 | 0.3x | identical |
| Zlib (text) | 133 | 445 | 0.3x | identical |
| Deflate (random) | 26 | 58 | 0.4x | identical |
| Gzip (random) | 28 | 55 | 0.5x | identical |
| Zlib (random) | 27 | 56 | 0.5x | identical |

### Decompression

| Format | Z (MB/s) | stdlib/libz (MB/s) | Z / stdlib |
|---|--:|--:|--:|
| Deflate (text) | 2,910 | 4,749 | 0.6x |
| Gzip (text) | 766 | 4,547 | 0.2x |
| Zlib (text) | 633 | 3,926 | 0.2x |

Compression ratios are identical to libz at every level. Throughput is lower since this is pure Crystal with no C code — the tradeoff is zero native dependencies and full portability.

Run the benchmarks yourself:

```bash
crystal build --release bench/comparison_bench.cr -o bench/comparison_bench
./bench/comparison_bench
```

## How it works

The implementation is fully compliant with the RFC specifications:

- **LZ77** sliding window (32 KB) with hash-chain match finding and lazy matching at levels >= 4
- **Huffman coding** with two-level lookup tables for decoding (11-bit primary + secondary) and canonical code generation for encoding
- **Block selection** automatically chooses between stored, fixed Huffman, and dynamic Huffman blocks based on estimated encoded size
- **Checksums** are pure Crystal: Adler-32 with the Nmax=5552 deferred-modulo optimization, CRC-32 with a precomputed 256-entry table
- **RFC compliance** includes reserved-bit validation, header CRC16 (FHCRC) verification, trailer checksum enforcement, and correct XFL compression hints

## Development

```
crystal spec
```

## License

[MIT](LICENSE)
