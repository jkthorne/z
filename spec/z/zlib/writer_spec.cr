require "../../spec_helper"
require "compress/zlib"

describe Z::Zlib::Writer do
  it "round-trips through Z writer and Z reader" do
    original = "Hello, zlib! Testing pure Crystal compression."

    compressed = IO::Memory.new
    Z::Zlib::Writer.open(compressed) { |w| w.print original }
    compressed.rewind

    result = Z::Zlib::Reader.open(compressed) { |r| r.gets_to_end }
    result.should eq(original)
  end

  it "output can be decompressed by stdlib" do
    original = "Cross-compatibility test for zlib format."

    compressed = IO::Memory.new
    Z::Zlib::Writer.open(compressed) { |w| w.print original }
    compressed.rewind

    result = Compress::Zlib::Reader.open(compressed) { |r| r.gets_to_end }
    result.should eq(original)
  end

  it "round-trips empty data" do
    compressed = IO::Memory.new
    Z::Zlib::Writer.open(compressed) { }
    compressed.rewind

    result = Z::Zlib::Reader.open(compressed) { |r| r.gets_to_end }
    result.should eq("")
  end

  it "round-trips large data" do
    original = String.build do |sb|
      500.times { |i| sb << "zlib record #{i}: some payload.\n" }
    end

    compressed = IO::Memory.new
    Z::Zlib::Writer.open(compressed) { |w| w.print original }
    compressed.rewind

    result = Z::Zlib::Reader.open(compressed) { |r| r.gets_to_end }
    result.should eq(original)
  end

  it "bidirectional cross-validation with stdlib" do
    original = "Testing both directions of zlib compatibility." * 20

    # Z compress -> stdlib decompress
    compressed = IO::Memory.new
    Z::Zlib::Writer.open(compressed) { |w| w.print original }
    compressed.rewind
    result1 = Compress::Zlib::Reader.open(compressed) { |r| r.gets_to_end }
    result1.should eq(original)

    # Stdlib compress -> Z decompress
    compressed2 = IO::Memory.new
    Compress::Zlib::Writer.open(compressed2) { |w| w.print original }
    compressed2.rewind
    result2 = Z::Zlib::Reader.open(compressed2) { |r| r.gets_to_end }
    result2.should eq(original)
  end
end
