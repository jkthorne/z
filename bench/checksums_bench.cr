require "./bench_helper"
require "digest/crc32"

BenchHelper.report_header("Checksum Benchmarks")

# Prevent dead-code elimination
sink = 0_u32

# --- CRC32 ---

BenchHelper.report_subheader("CRC32 — Full buffer")

{BenchHelper::SIZE_1M, BenchHelper::SIZE_10M}.each do |size|
  label = BenchHelper.format_size(size)
  data = BenchHelper.generate_random(size)

  elapsed = BenchHelper.measure(5) { sink &+= Z::CRC32.checksum(data) }
  tp = BenchHelper.throughput_mb_s(size, elapsed)
  printf "  Z::CRC32          %6s  %8.1f MB/s  (%s)\n", label, tp, elapsed

  elapsed = BenchHelper.measure(5) { sink &+= Digest::CRC32.checksum(data).to_u32 }
  tp = BenchHelper.throughput_mb_s(size, elapsed)
  printf "  Digest::CRC32     %6s  %8.1f MB/s  (%s)\n", label, tp, elapsed
end

BenchHelper.report_subheader("CRC32 — Incremental (chunked)")

data_1m = BenchHelper.generate_random(BenchHelper::SIZE_1M)

{4096, 65536}.each do |chunk_size|
  label = "#{chunk_size // 1024} KB chunks"

  elapsed = BenchHelper.measure(5) do
    crc = Z::CRC32.initial
    offset = 0
    while offset < data_1m.size
      end_pos = Math.min(offset + chunk_size, data_1m.size)
      crc = Z::CRC32.update(data_1m[offset, end_pos - offset], crc)
      offset = end_pos
    end
    sink &+= Z::CRC32.finalize(crc)
  end
  tp = BenchHelper.throughput_mb_s(BenchHelper::SIZE_1M, elapsed)
  printf "  Z::CRC32          %-16s  %8.1f MB/s  (%s)\n", label, tp, elapsed
end

# --- Adler32 ---

BenchHelper.report_subheader("Adler32 — Full buffer")

{BenchHelper::SIZE_1M, BenchHelper::SIZE_10M}.each do |size|
  label = BenchHelper.format_size(size)
  data = BenchHelper.generate_random(size)

  elapsed = BenchHelper.measure(5) { sink &+= Z::Adler32.checksum(data) }
  tp = BenchHelper.throughput_mb_s(size, elapsed)
  printf "  Z::Adler32        %6s  %8.1f MB/s  (%s)\n", label, tp, elapsed
end

BenchHelper.report_subheader("Adler32 — Incremental (chunked)")

{4096, 65536}.each do |chunk_size|
  label = "#{chunk_size // 1024} KB chunks"

  elapsed = BenchHelper.measure(5) do
    adler = Z::Adler32.initial
    offset = 0
    while offset < data_1m.size
      end_pos = Math.min(offset + chunk_size, data_1m.size)
      adler = Z::Adler32.update(data_1m[offset, end_pos - offset], adler)
      offset = end_pos
    end
    sink &+= adler
  end
  tp = BenchHelper.throughput_mb_s(BenchHelper::SIZE_1M, elapsed)
  printf "  Z::Adler32        %-16s  %8.1f MB/s  (%s)\n", label, tp, elapsed
end

puts
puts "(sink=#{sink})" # Ensure sink is used
