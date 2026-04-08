require "../../spec_helper"
require "compress/deflate"

describe Z::Deflate::Writer do
  it "round-trips simple text" do
    original = "Hello, World! This is a test of pure Crystal DEFLATE compression."

    compressed = IO::Memory.new
    Z::Deflate::Writer.open(compressed) do |w|
      w.print original
    end
    compressed.rewind

    result = Z::Deflate::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end

  it "round-trips empty data" do
    compressed = IO::Memory.new
    Z::Deflate::Writer.open(compressed) { }
    compressed.rewind

    result = Z::Deflate::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq("")
  end

  it "round-trips repetitive data" do
    original = "ABCDEFGH" * 500

    compressed = IO::Memory.new
    Z::Deflate::Writer.open(compressed) do |w|
      w.print original
    end
    compressed.rewind

    result = Z::Deflate::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end

  it "output can be decompressed by stdlib" do
    original = "Testing cross-compatibility with Crystal stdlib Deflate."

    compressed = IO::Memory.new
    Z::Deflate::Writer.open(compressed) do |w|
      w.print original
    end
    compressed.rewind

    result = Compress::Deflate::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end

  it "round-trips with level 0 (store)" do
    original = "Stored without compression."

    compressed = IO::Memory.new
    Z::Deflate::Writer.open(compressed, level: 0) do |w|
      w.print original
    end
    compressed.rewind

    result = Z::Deflate::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end

  it "round-trips random data" do
    random = Random.new(42)
    original = Bytes.new(5000) { random.rand(256).to_u8 }

    compressed = IO::Memory.new
    Z::Deflate::Writer.open(compressed) do |w|
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

  it "round-trips with various compression levels" do
    original = "Testing compression levels." * 50

    [1, 3, 6, 9].each do |level|
      compressed = IO::Memory.new
      Z::Deflate::Writer.open(compressed, level: level) do |w|
        w.print original
      end
      compressed.rewind

      result = Z::Deflate::Reader.open(compressed) do |r|
        r.gets_to_end
      end
      result.should eq(original), "Failed at level #{level}"
    end
  end

  it "handles incremental writes" do
    parts = ["Hello, ", "World! ", "How ", "are ", "you?"]
    original = parts.join

    compressed = IO::Memory.new
    Z::Deflate::Writer.open(compressed) do |w|
      parts.each { |p| w.print p }
    end
    compressed.rewind

    result = Z::Deflate::Reader.open(compressed) do |r|
      r.gets_to_end
    end
    result.should eq(original)
  end
end
