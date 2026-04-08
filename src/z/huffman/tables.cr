module Z
  module Huffman
    # Length codes 257-285: base length and extra bits
    LENGTH_BASE = StaticArray[
      3, 4, 5, 6, 7, 8, 9, 10,       # 257-264
      11, 13, 15, 17,                  # 265-268
      19, 23, 27, 31,                  # 269-272
      35, 43, 51, 59,                  # 273-276
      67, 83, 99, 115,                 # 277-280
      131, 163, 195, 227,             # 281-284
      258,                             # 285
    ]

    LENGTH_EXTRA = StaticArray[
      0, 0, 0, 0, 0, 0, 0, 0,  # 257-264
      1, 1, 1, 1,               # 265-268
      2, 2, 2, 2,               # 269-272
      3, 3, 3, 3,               # 273-276
      4, 4, 4, 4,               # 277-280
      5, 5, 5, 5,               # 281-284
      0,                         # 285
    ]

    # Distance codes 0-29: base distance and extra bits
    DISTANCE_BASE = StaticArray[
      1, 2, 3, 4, 5, 7, 9, 13,
      17, 25, 33, 49, 65, 97, 129, 193,
      257, 385, 513, 769, 1025, 1537, 2049, 3073,
      4097, 6145, 8193, 12289, 16385, 24577,
    ]

    DISTANCE_EXTRA = StaticArray[
      0, 0, 0, 0, 1, 1, 2, 2,
      3, 3, 4, 4, 5, 5, 6, 6,
      7, 7, 8, 8, 9, 9, 10, 10,
      11, 11, 12, 12, 13, 13,
    ]

    # Reverse lookup: length (3..258) -> length code (257..285)
    # Index by (length - 3)
    LENGTH_TO_CODE = begin
      table = StaticArray(UInt16, 259).new(0_u16)
      LENGTH_BASE.each_with_index do |base, i|
        next_base = i + 1 < LENGTH_BASE.size ? LENGTH_BASE[i + 1] : 259
        (base...next_base).each do |len|
          table[len - 3] = (i + 257).to_u16 if len - 3 < 259
        end
      end
      table
    end

    # Code length alphabet order (RFC 1951 section 3.2.7)
    CODE_LENGTH_ORDER = StaticArray[
      16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
    ]

    # Byte-reversal lookup table for fast bit reversal
    REVERSE_BYTE = begin
      table = StaticArray(UInt8, 256).new(0_u8)
      256.times do |i|
        r = 0_u8
        v = i.to_u8
        8.times do
          r = (r << 1) | (v & 1)
          v >>= 1
        end
        table[i] = r
      end
      table
    end

    # Reverse n bits (n <= 16) using byte-reversal table
    def self.reverse_bits(value : UInt32, n : Int32) : UInt32
      # Reverse 16 bits via two byte lookups, then shift right by (16 - n)
      lo = REVERSE_BYTE[value & 0xFF].to_u32
      hi = REVERSE_BYTE[(value >> 8) & 0xFF].to_u32
      ((lo << 8) | hi) >> (16 - n)
    end

    # Fixed literal/length code lengths (RFC 1951 section 3.2.6)
    FIXED_LITERAL_LENGTHS = begin
      lengths = StaticArray(UInt8, 288).new(0_u8)
      (0..143).each { |i| lengths[i] = 8_u8 }
      (144..255).each { |i| lengths[i] = 9_u8 }
      (256..279).each { |i| lengths[i] = 7_u8 }
      (280..287).each { |i| lengths[i] = 8_u8 }
      lengths
    end

    # Fixed distance code lengths (all 5 bits)
    FIXED_DISTANCE_LENGTHS = begin
      lengths = StaticArray(UInt8, 32).new(5_u8)
      lengths
    end
  end
end
