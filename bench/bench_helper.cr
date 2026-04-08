require "benchmark"
require "random"
require "../src/z"

module BenchHelper
  # Standard data sizes
  SIZE_1K   =     1_024
  SIZE_100K =   100_000
  SIZE_1M   = 1_000_000
  SIZE_10M  = 10_000_000

  SIZES = {
    "1 KB"   => SIZE_1K,
    "100 KB" => SIZE_100K,
    "1 MB"   => SIZE_1M,
  }

  # Generate highly compressible English-like text
  def self.generate_text(size : Int32) : Bytes
    prose = "The quick brown fox jumps over the lazy dog. " \
            "Pack my box with five dozen liquor jugs. " \
            "How vexingly quick daft zebras jump. " \
            "Sphinx of black quartz, judge my vow. " \
            "Two driven jocks help fax my big quiz. "
    buf = IO::Memory.new(size)
    while buf.pos < size
      buf << prose
    end
    buf.rewind
    buf.to_slice[0, size].dup
  end

  # Generate moderately compressible structured data (JSON-like)
  def self.generate_mixed(size : Int32) : Bytes
    rng = Random.new(12345)
    buf = IO::Memory.new(size)
    id = 0
    while buf.pos < size
      id += 1
      buf << %({"id":#{id},"name":"user_#{rng.rand(10000)}",)
      buf << %("score":#{rng.rand(100)},)
      buf << %("active":#{rng.rand(2) == 1},)
      buf << %("tags":["tag_#{rng.rand(50)}","tag_#{rng.rand(50)}"]}\n)
    end
    buf.rewind
    buf.to_slice[0, size].dup
  end

  # Generate incompressible random bytes
  def self.generate_random(size : Int32) : Bytes
    rng = Random.new(42)
    Bytes.new(size) { rng.rand(256).to_u8 }
  end

  DATA_TYPES = {"text", "mixed", "random"}

  def self.generate(type : String, size : Int32) : Bytes
    case type
    when "text"   then generate_text(size)
    when "mixed"  then generate_mixed(size)
    when "random" then generate_random(size)
    else               raise "Unknown data type: #{type}"
    end
  end

  # Reporting helpers
  def self.throughput_mb_s(bytes : Int, elapsed : Time::Span) : Float64
    mb = bytes.to_f64 / (1024 * 1024)
    secs = elapsed.total_seconds
    secs > 0 ? mb / secs : 0.0
  end

  def self.ratio_percent(original : Int, compressed : Int) : Float64
    original > 0 ? (compressed.to_f64 / original * 100) : 0.0
  end

  def self.report_header(title : String)
    puts
    puts "=" * 70
    puts " #{title}"
    puts "=" * 70
  end

  def self.report_subheader(title : String)
    puts
    puts "--- #{title} ---"
  end

  # Compress data and return compressed bytes
  def self.deflate_compress(data : Bytes, level : Int32 = Z::Deflate::DEFAULT_COMPRESSION) : Bytes
    output = IO::Memory.new
    Z::Deflate::Writer.open(output, level: level) do |w|
      w.write(data)
    end
    output.rewind
    output.to_slice.dup
  end

  def self.deflate_decompress(compressed : Bytes) : Bytes
    input = IO::Memory.new(compressed)
    output = IO::Memory.new
    Z::Deflate::Reader.open(input) do |r|
      IO.copy(r, output)
    end
    output.rewind
    output.to_slice.dup
  end

  def self.gzip_compress(data : Bytes, level : Int32 = Z::Deflate::DEFAULT_COMPRESSION) : Bytes
    output = IO::Memory.new
    Z::Gzip::Writer.open(output, level: level) do |w|
      w.write(data)
    end
    output.rewind
    output.to_slice.dup
  end

  def self.zlib_compress(data : Bytes, level : Int32 = Z::Deflate::DEFAULT_COMPRESSION) : Bytes
    output = IO::Memory.new
    Z::Zlib::Writer.open(output, level: level) do |w|
      w.write(data)
    end
    output.rewind
    output.to_slice.dup
  end

  def self.format_size(size : Int32) : String
    if size >= 1_000_000
      "#{size // 1_000_000} MB"
    elsif size >= 1_000
      "#{size // 1_000} KB"
    else
      "#{size} B"
    end
  end

  # Measure a block N times and return the best elapsed time.
  # For very fast operations, the block is repeated internally to get
  # a measurable duration. Returns elapsed time per single invocation.
  def self.measure(iterations : Int32 = 3, min_time : Time::Span = 100.milliseconds, &block) : Time::Span
    # Calibrate: find how many reps needed to fill min_time
    reps = 1
    loop do
      elapsed = Time.measure { reps.times { block.call } }
      if elapsed >= min_time || reps >= 1_000_000
        break
      end
      reps *= (elapsed.total_seconds > 0 ? (min_time.total_seconds / elapsed.total_seconds).ceil.to_i : 10)
      reps = reps.clamp(1, 1_000_000)
    end

    best = Time::Span::MAX
    iterations.times do
      elapsed = Time.measure { reps.times { block.call } }
      per_call = elapsed / reps
      best = per_call if per_call < best
    end
    best
  end
end
