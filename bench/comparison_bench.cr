require "./bench_helper"
require "compress/deflate"
require "compress/gzip"
require "compress/zlib"

BenchHelper.report_header("Z vs Crystal stdlib (libz) Comparison")

size = BenchHelper::SIZE_1M
level = Z::Deflate::DEFAULT_COMPRESSION

{"text", "random"}.each do |dtype|
  data = BenchHelper.generate(dtype, size)

  BenchHelper.report_subheader("#{dtype} data (1 MB, level #{level})")

  # ===================== Compression =====================

  printf "\n  %-28s  %10s  %8s  %s\n", "Compression", "Ratio", "MB/s", "Time"
  printf "  %-28s  %10s  %8s  %s\n", "-----------", "-----", "----", "----"

  # --- Deflate ---

  z_compressed = BenchHelper.deflate_compress(data, level)
  elapsed_z = BenchHelper.measure(3) { BenchHelper.deflate_compress(data, level) }
  tp_z = BenchHelper.throughput_mb_s(size, elapsed_z)
  ratio_z = BenchHelper.ratio_percent(size, z_compressed.size)
  printf "  %-28s  %9.1f%%  %7.1f  %s\n", "Z::Deflate::Writer", ratio_z, tp_z, elapsed_z

  stdlib_compressed = IO::Memory.new
  Compress::Deflate::Writer.open(stdlib_compressed) { |w| w.write(data) }
  stdlib_compressed.rewind
  stdlib_deflate = stdlib_compressed.to_slice.dup

  elapsed_s = BenchHelper.measure(3) do
    io = IO::Memory.new
    Compress::Deflate::Writer.open(io) { |w| w.write(data) }
  end
  tp_s = BenchHelper.throughput_mb_s(size, elapsed_s)
  ratio_s = BenchHelper.ratio_percent(size, stdlib_deflate.size)
  printf "  %-28s  %9.1f%%  %7.1f  %s\n", "Compress::Deflate::Writer", ratio_s, tp_s, elapsed_s

  if tp_s > 0
    printf "  %-28s  %10s  %7.1fx\n", "  → Z / stdlib speed", "", tp_z / tp_s
  end

  # --- Gzip ---

  z_gz = BenchHelper.gzip_compress(data, level)
  elapsed_z = BenchHelper.measure(3) { BenchHelper.gzip_compress(data, level) }
  tp_z = BenchHelper.throughput_mb_s(size, elapsed_z)
  ratio_z = BenchHelper.ratio_percent(size, z_gz.size)
  printf "  %-28s  %9.1f%%  %7.1f  %s\n", "Z::Gzip::Writer", ratio_z, tp_z, elapsed_z

  stdlib_gz_io = IO::Memory.new
  Compress::Gzip::Writer.open(stdlib_gz_io) { |w| w.write(data) }
  stdlib_gz_io.rewind
  stdlib_gz = stdlib_gz_io.to_slice.dup

  elapsed_s = BenchHelper.measure(3) do
    io = IO::Memory.new
    Compress::Gzip::Writer.open(io) { |w| w.write(data) }
  end
  tp_s = BenchHelper.throughput_mb_s(size, elapsed_s)
  ratio_s = BenchHelper.ratio_percent(size, stdlib_gz.size)
  printf "  %-28s  %9.1f%%  %7.1f  %s\n", "Compress::Gzip::Writer", ratio_s, tp_s, elapsed_s

  if tp_s > 0
    printf "  %-28s  %10s  %7.1fx\n", "  → Z / stdlib speed", "", tp_z / tp_s
  end

  # --- Zlib ---

  z_zlib = BenchHelper.zlib_compress(data, level)
  elapsed_z = BenchHelper.measure(3) { BenchHelper.zlib_compress(data, level) }
  tp_z = BenchHelper.throughput_mb_s(size, elapsed_z)
  ratio_z = BenchHelper.ratio_percent(size, z_zlib.size)
  printf "  %-28s  %9.1f%%  %7.1f  %s\n", "Z::Zlib::Writer", ratio_z, tp_z, elapsed_z

  stdlib_zlib_io = IO::Memory.new
  Compress::Zlib::Writer.open(stdlib_zlib_io) { |w| w.write(data) }
  stdlib_zlib_io.rewind
  stdlib_zlib = stdlib_zlib_io.to_slice.dup

  elapsed_s = BenchHelper.measure(3) do
    io = IO::Memory.new
    Compress::Zlib::Writer.open(io) { |w| w.write(data) }
  end
  tp_s = BenchHelper.throughput_mb_s(size, elapsed_s)
  ratio_s = BenchHelper.ratio_percent(size, stdlib_zlib.size)
  printf "  %-28s  %9.1f%%  %7.1f  %s\n", "Compress::Zlib::Writer", ratio_s, tp_s, elapsed_s

  if tp_s > 0
    printf "  %-28s  %10s  %7.1fx\n", "  → Z / stdlib speed", "", tp_z / tp_s
  end

  # ===================== Decompression =====================

  printf "\n  %-28s  %10s  %8s  %s\n", "Decompression", "", "MB/s", "Time"
  printf "  %-28s  %10s  %8s  %s\n", "-------------", "", "----", "----"

  # --- Deflate read ---

  elapsed_z = BenchHelper.measure(3) do
    input = IO::Memory.new(z_compressed)
    output = IO::Memory.new(size)
    Z::Deflate::Reader.open(input) { |r| IO.copy(r, output) }
  end
  tp_z = BenchHelper.throughput_mb_s(size, elapsed_z)
  printf "  %-28s  %10s  %7.1f  %s\n", "Z::Deflate::Reader", "", tp_z, elapsed_z

  elapsed_s = BenchHelper.measure(3) do
    input = IO::Memory.new(stdlib_deflate)
    output = IO::Memory.new(size)
    Compress::Deflate::Reader.open(input) { |r| IO.copy(r, output) }
  end
  tp_s = BenchHelper.throughput_mb_s(size, elapsed_s)
  printf "  %-28s  %10s  %7.1f  %s\n", "Compress::Deflate::Reader", "", tp_s, elapsed_s

  if tp_s > 0
    printf "  %-28s  %10s  %7.1fx\n", "  → Z / stdlib speed", "", tp_z / tp_s
  end

  # --- Gzip read ---

  elapsed_z = BenchHelper.measure(3) do
    input = IO::Memory.new(z_gz)
    output = IO::Memory.new(size)
    Z::Gzip::Reader.open(input) { |r| IO.copy(r, output) }
  end
  tp_z = BenchHelper.throughput_mb_s(size, elapsed_z)
  printf "  %-28s  %10s  %7.1f  %s\n", "Z::Gzip::Reader", "", tp_z, elapsed_z

  elapsed_s = BenchHelper.measure(3) do
    input = IO::Memory.new(stdlib_gz)
    output = IO::Memory.new(size)
    Compress::Gzip::Reader.open(input) { |r| IO.copy(r, output) }
  end
  tp_s = BenchHelper.throughput_mb_s(size, elapsed_s)
  printf "  %-28s  %10s  %7.1f  %s\n", "Compress::Gzip::Reader", "", tp_s, elapsed_s

  if tp_s > 0
    printf "  %-28s  %10s  %7.1fx\n", "  → Z / stdlib speed", "", tp_z / tp_s
  end

  # --- Zlib read ---

  elapsed_z = BenchHelper.measure(3) do
    input = IO::Memory.new(z_zlib)
    output = IO::Memory.new(size)
    Z::Zlib::Reader.open(input) { |r| IO.copy(r, output) }
  end
  tp_z = BenchHelper.throughput_mb_s(size, elapsed_z)
  printf "  %-28s  %10s  %7.1f  %s\n", "Z::Zlib::Reader", "", tp_z, elapsed_z

  elapsed_s = BenchHelper.measure(3) do
    input = IO::Memory.new(stdlib_zlib)
    output = IO::Memory.new(size)
    Compress::Zlib::Reader.open(input) { |r| IO.copy(r, output) }
  end
  tp_s = BenchHelper.throughput_mb_s(size, elapsed_s)
  printf "  %-28s  %10s  %7.1f  %s\n", "Compress::Zlib::Reader", "", tp_s, elapsed_s

  if tp_s > 0
    printf "  %-28s  %10s  %7.1fx\n", "  → Z / stdlib speed", "", tp_z / tp_s
  end
end

puts
