require "../../spec_helper"
require "compress/deflate"

describe Z::Deflate::Reader do
  it "decompresses data from stdlib Compress::Deflate::Writer" do
    original = "Hello, World! This is a test of DEFLATE decompression."

    compressed = IO::Memory.new
    Compress::Deflate::Writer.open(compressed) do |w|
      w.print original
    end
    compressed.rewind

    result = Z::Deflate::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end

  it "decompresses empty data" do
    compressed = IO::Memory.new
    Compress::Deflate::Writer.open(compressed) do |w|
      # Write nothing
    end
    compressed.rewind

    result = Z::Deflate::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq("")
  end

  it "decompresses single byte" do
    compressed = IO::Memory.new
    Compress::Deflate::Writer.open(compressed) do |w|
      w.write_byte(42_u8)
    end
    compressed.rewind

    result = Z::Deflate::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.bytes.should eq([42])
  end

  it "decompresses data with back-references" do
    # Highly repetitive data forces back-references
    original = "ABCABCABCABCABCABCABCABCABCABC" * 10

    compressed = IO::Memory.new
    Compress::Deflate::Writer.open(compressed) do |w|
      w.print original
    end
    compressed.rewind

    result = Z::Deflate::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end

  it "decompresses larger data" do
    original = String.build do |sb|
      1000.times { |i| sb << "Line #{i}: The quick brown fox jumps over the lazy dog.\n" }
    end

    compressed = IO::Memory.new
    Compress::Deflate::Writer.open(compressed) do |w|
      w.print original
    end
    compressed.rewind

    result = Z::Deflate::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end

  it "decompresses random-ish data" do
    random = Random.new(42)
    original = Bytes.new(5000) { random.rand(256).to_u8 }

    compressed = IO::Memory.new
    Compress::Deflate::Writer.open(compressed) do |w|
      w.write(original)
    end
    compressed.rewind

    result = IO::Memory.new
    Z::Deflate::Reader.open(compressed) do |r|
      IO.copy(r, result)
    end
    result.rewind
    result.to_slice.should eq(original)
  end

  it "supports block-based reads" do
    original = "Hello, World!" * 100

    compressed = IO::Memory.new
    Compress::Deflate::Writer.open(compressed) do |w|
      w.print original
    end
    compressed.rewind

    reader = Z::Deflate::Reader.new(compressed)
    result = IO::Memory.new
    buf = Bytes.new(7)  # Deliberately small buffer
    loop do
      count = reader.read(buf)
      break if count == 0
      result.write(buf[0, count])
    end
    reader.close

    result.rewind
    String.new(result.to_slice).should eq(original)
  end
end
