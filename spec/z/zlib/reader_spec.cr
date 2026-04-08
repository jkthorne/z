require "../../spec_helper"
require "compress/zlib"

describe Z::Zlib::Reader do
  it "decompresses data from stdlib Compress::Zlib::Writer" do
    original = "Hello, zlib World! Compression is working great."

    compressed = IO::Memory.new
    Compress::Zlib::Writer.open(compressed) do |w|
      w.print original
    end
    compressed.rewind

    result = Z::Zlib::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end

  it "decompresses empty data" do
    compressed = IO::Memory.new
    Compress::Zlib::Writer.open(compressed) { }
    compressed.rewind

    result = Z::Zlib::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq("")
  end

  it "decompresses larger data with checksum verification" do
    original = String.build do |sb|
      500.times { |i| sb << "Record #{i}: some test data here.\n" }
    end

    compressed = IO::Memory.new
    Compress::Zlib::Writer.open(compressed) do |w|
      w.print original
    end
    compressed.rewind

    result = Z::Zlib::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end

  it "raises on invalid header" do
    io = IO::Memory.new(Bytes[0x00, 0x00])
    expect_raises(Z::Zlib::Error) do
      Z::Zlib::Reader.new(io)
    end
  end
end
