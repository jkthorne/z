require "./bench_helper"

BenchHelper.report_header("DEFLATE Compression Benchmarks")

levels = {1, 3, 6, 9}
size = BenchHelper::SIZE_1M

# Generate test data
datasets = {} of String => Bytes
BenchHelper::DATA_TYPES.each do |dtype|
  datasets[dtype] = BenchHelper.generate(dtype, size)
end

# --- Compression ---

BenchHelper.report_subheader("Compression (1 MB input)")
printf "  %-8s  %5s  %10s  %8s  %s\n", "Data", "Level", "Ratio", "MB/s", "Time"
printf "  %-8s  %5s  %10s  %8s  %s\n", "----", "-----", "-----", "----", "----"

compressed_cache = {} of String => Bytes

BenchHelper::DATA_TYPES.each do |dtype|
  data = datasets[dtype]
  levels.each do |level|
    key = "#{dtype}-#{level}"

    # Warm up and capture compressed output
    compressed = BenchHelper.deflate_compress(data, level)
    compressed_cache[key] = compressed

    elapsed = BenchHelper.measure(3) { BenchHelper.deflate_compress(data, level) }
    tp = BenchHelper.throughput_mb_s(size, elapsed)
    ratio = BenchHelper.ratio_percent(size, compressed.size)

    printf "  %-8s  %5d  %9.1f%%  %7.1f  %s\n", dtype, level, ratio, tp, elapsed
  end
end

# --- Decompression ---

BenchHelper.report_subheader("Decompression (1 MB original)")
printf "  %-8s  %5s  %8s  %s\n", "Data", "Level", "MB/s", "Time"
printf "  %-8s  %5s  %8s  %s\n", "----", "-----", "----", "----"

BenchHelper::DATA_TYPES.each do |dtype|
  levels.each do |level|
    key = "#{dtype}-#{level}"
    compressed = compressed_cache[key]

    # Verify round-trip
    decompressed = BenchHelper.deflate_decompress(compressed)
    raise "Round-trip failed for #{key}" unless decompressed == datasets[dtype]

    elapsed = BenchHelper.measure(3) do
      input = IO::Memory.new(compressed)
      output = IO::Memory.new(size)
      Z::Deflate::Reader.open(input) do |r|
        IO.copy(r, output)
      end
    end
    tp = BenchHelper.throughput_mb_s(size, elapsed)

    printf "  %-8s  %5d  %7.1f  %s\n", dtype, level, tp, elapsed
  end
end

# --- Size scaling ---

BenchHelper.report_subheader("Compression throughput scaling (level 6, text)")

BenchHelper::SIZES.each do |label, sz|
  data = BenchHelper.generate_text(sz)

  elapsed = BenchHelper.measure(3) { BenchHelper.deflate_compress(data, 6) }
  tp = BenchHelper.throughput_mb_s(sz, elapsed)
  printf "  %-8s  %8.1f MB/s  (%s)\n", label, tp, elapsed
end

puts
