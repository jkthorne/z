require "../../spec_helper"
require "compress/gzip"

describe Z::Gzip::Reader do
  it "decompresses data from stdlib Compress::Gzip::Writer" do
    original = "Hello, gzip World! Compression is working great."

    compressed = IO::Memory.new
    Compress::Gzip::Writer.open(compressed) do |w|
      w.print original
    end
    compressed.rewind

    result = Z::Gzip::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end

  it "decompresses empty data" do
    compressed = IO::Memory.new
    Compress::Gzip::Writer.open(compressed) { }
    compressed.rewind

    result = Z::Gzip::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq("")
  end

  it "decompresses larger data" do
    original = String.build do |sb|
      500.times { |i| sb << "Line #{i}: gzip test data with various content.\n" }
    end

    compressed = IO::Memory.new
    Compress::Gzip::Writer.open(compressed) do |w|
      w.print original
    end
    compressed.rewind

    result = Z::Gzip::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end

  it "reads header metadata" do
    compressed = IO::Memory.new
    Compress::Gzip::Writer.open(compressed) do |w|
      w.print "test"
    end
    compressed.rewind

    reader = Z::Gzip::Reader.new(compressed)
    reader.header.should_not be_nil
    reader.gets_to_end
    reader.close
  end

  it "raises on invalid magic bytes" do
    io = IO::Memory.new(Bytes[0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    expect_raises(Z::Gzip::Error, "Invalid gzip magic") do
      Z::Gzip::Reader.new(io)
    end
  end

  it "decompresses random data" do
    random = Random.new(123)
    original = Bytes.new(3000) { random.rand(256).to_u8 }

    compressed = IO::Memory.new
    Compress::Gzip::Writer.open(compressed) do |w|
      w.write(original)
    end
    compressed.rewind

    result = IO::Memory.new
    Z::Gzip::Reader.open(compressed) do |r|
      IO.copy(r, result)
    end
    result.rewind
    result.to_slice.should eq(original)
  end
end
