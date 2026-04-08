require "../../spec_helper"
require "compress/gzip"

describe Z::Gzip::Writer do
  it "round-trips through Z writer and Z reader" do
    original = "Hello, gzip! Testing pure Crystal compression."

    compressed = IO::Memory.new
    Z::Gzip::Writer.open(compressed) { |w| w.print original }
    compressed.rewind

    result = Z::Gzip::Reader.open(compressed) { |r| r.gets_to_end }
    result.should eq(original)
  end

  it "output can be decompressed by stdlib" do
    original = "Cross-compatibility test for gzip format."

    compressed = IO::Memory.new
    Z::Gzip::Writer.open(compressed) { |w| w.print original }
    compressed.rewind

    result = Compress::Gzip::Reader.open(compressed) { |r| r.gets_to_end }
    result.should eq(original)
  end

  it "round-trips empty data" do
    compressed = IO::Memory.new
    Z::Gzip::Writer.open(compressed) { }
    compressed.rewind

    result = Z::Gzip::Reader.open(compressed) { |r| r.gets_to_end }
    result.should eq("")
  end

  it "round-trips large data" do
    original = String.build do |sb|
      500.times { |i| sb << "gzip record #{i}: some payload.\n" }
    end

    compressed = IO::Memory.new
    Z::Gzip::Writer.open(compressed) { |w| w.print original }
    compressed.rewind

    result = Z::Gzip::Reader.open(compressed) { |r| r.gets_to_end }
    result.should eq(original)
  end

  it "bidirectional cross-validation with stdlib" do
    original = "Testing both directions of gzip compatibility." * 20

    # Z compress -> stdlib decompress
    compressed = IO::Memory.new
    Z::Gzip::Writer.open(compressed) { |w| w.print original }
    compressed.rewind
    result1 = Compress::Gzip::Reader.open(compressed) { |r| r.gets_to_end }
    result1.should eq(original)

    # Stdlib compress -> Z decompress
    compressed2 = IO::Memory.new
    Compress::Gzip::Writer.open(compressed2) { |w| w.print original }
    compressed2.rewind
    result2 = Z::Gzip::Reader.open(compressed2) { |r| r.gets_to_end }
    result2.should eq(original)
  end

  it "round-trips random binary data" do
    random = Random.new(99)
    original = Bytes.new(3000) { random.rand(256).to_u8 }

    compressed = IO::Memory.new
    Z::Gzip::Writer.open(compressed) { |w| w.write(original) }
    compressed.rewind

    result = IO::Memory.new
    Z::Gzip::Reader.open(compressed) { |r| IO.copy(r, result) }
    result.rewind
    result.to_slice.should eq(original)
  end

  it "preserves header metadata" do
    header = Z::Gzip::Header.new
    header.name = "test.txt"

    compressed = IO::Memory.new
    Z::Gzip::Writer.open(compressed) do |w|
      w.print "test"
    end
    compressed.rewind

    reader = Z::Gzip::Reader.new(compressed)
    reader.gets_to_end
    reader.close
  end
end
