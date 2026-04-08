require "./bench_helper"

BenchHelper.report_header("Format Wrapper Benchmarks (Gzip / Zlib / Raw Deflate)")

size = BenchHelper::SIZE_1M
level = Z::Deflate::DEFAULT_COMPRESSION

BenchHelper::DATA_TYPES.each do |dtype|
  data = BenchHelper.generate(dtype, size)

  BenchHelper.report_subheader("#{dtype} data (1 MB, level #{level})")
  printf "  %-16s  %10s  %8s  %s\n", "Format", "Ratio", "MB/s", "Time"
  printf "  %-16s  %10s  %8s  %s\n", "------", "-----", "----", "----"

  # --- Compression ---

  # Raw Deflate
  compressed = BenchHelper.deflate_compress(data, level)
  elapsed = BenchHelper.measure(3) { BenchHelper.deflate_compress(data, level) }
  tp = BenchHelper.throughput_mb_s(size, elapsed)
  ratio = BenchHelper.ratio_percent(size, compressed.size)
  printf "  %-16s  %9.1f%%  %7.1f  %s\n", "Deflate write", ratio, tp, elapsed

  # Gzip
  gz_compressed = BenchHelper.gzip_compress(data, level)
  elapsed = BenchHelper.measure(3) { BenchHelper.gzip_compress(data, level) }
  tp = BenchHelper.throughput_mb_s(size, elapsed)
  ratio = BenchHelper.ratio_percent(size, gz_compressed.size)
  printf "  %-16s  %9.1f%%  %7.1f  %s\n", "Gzip write", ratio, tp, elapsed

  # Zlib
  zlib_compressed = BenchHelper.zlib_compress(data, level)
  elapsed = BenchHelper.measure(3) { BenchHelper.zlib_compress(data, level) }
  tp = BenchHelper.throughput_mb_s(size, elapsed)
  ratio = BenchHelper.ratio_percent(size, zlib_compressed.size)
  printf "  %-16s  %9.1f%%  %7.1f  %s\n", "Zlib write", ratio, tp, elapsed

  # --- Decompression ---

  puts

  # Raw Deflate read
  elapsed = BenchHelper.measure(3) do
    input = IO::Memory.new(compressed)
    output = IO::Memory.new(size)
    Z::Deflate::Reader.open(input) { |r| IO.copy(r, output) }
  end
  tp = BenchHelper.throughput_mb_s(size, elapsed)
  printf "  %-16s  %10s  %7.1f  %s\n", "Deflate read", "", tp, elapsed

  # Gzip read
  elapsed = BenchHelper.measure(3) do
    input = IO::Memory.new(gz_compressed)
    output = IO::Memory.new(size)
    Z::Gzip::Reader.open(input) { |r| IO.copy(r, output) }
  end
  tp = BenchHelper.throughput_mb_s(size, elapsed)
  printf "  %-16s  %10s  %7.1f  %s\n", "Gzip read", "", tp, elapsed

  # Zlib read
  elapsed = BenchHelper.measure(3) do
    input = IO::Memory.new(zlib_compressed)
    output = IO::Memory.new(size)
    Z::Zlib::Reader.open(input) { |r| IO.copy(r, output) }
  end
  tp = BenchHelper.throughput_mb_s(size, elapsed)
  printf "  %-16s  %10s  %7.1f  %s\n", "Zlib read", "", tp, elapsed
end

puts
