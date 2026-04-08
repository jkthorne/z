module Z
  module CRC32
    POLYNOMIAL = 0xEDB88320_u32

    # Slicing-by-4 tables stored flat: index = table_num * 256 + byte_value
    # TABLES4[0..255] is the standard CRC table,
    # TABLES4[256..511], [512..767], [768..1023] are derived for multi-byte processing
    TABLES4 = begin
      tables = StaticArray(UInt32, 1024).new(0_u32)

      # Build base table (slot 0)
      256.times do |i|
        crc = i.to_u32
        8.times do
          if crc & 1 == 1
            crc = (crc >> 1) ^ POLYNOMIAL
          else
            crc >>= 1
          end
        end
        tables[i] = crc
      end

      # Build extended tables (slots 1..3)
      256.times do |i|
        crc = tables[i]
        (1..3).each do |t|
          crc = tables[crc & 0xFF] ^ (crc >> 8)
          tables[t * 256 + i] = crc
        end
      end

      tables
    end

    # Single-table view for byte-at-a-time fallback
    TABLE = begin
      table = StaticArray(UInt32, 256).new(0_u32)
      256.times { |i| table[i] = TABLES4[i] }
      table
    end

    def self.initial : UInt32
      0xFFFFFFFF_u32
    end

    def self.checksum(data : Bytes) : UInt32
      finalize(update(data, initial))
    end

    def self.checksum(str : String) : UInt32
      checksum(str.to_slice)
    end

    def self.update(data : Bytes, crc : UInt32) : UInt32
      ptr = data.to_unsafe
      remaining = data.size

      # Process 4 bytes at a time (slicing-by-4)
      while remaining >= 4
        val = crc ^ (ptr[0].to_u32 | (ptr[1].to_u32 << 8) | (ptr[2].to_u32 << 16) | (ptr[3].to_u32 << 24))
        crc = TABLES4[768 + (val & 0xFF)] ^ TABLES4[512 + ((val >> 8) & 0xFF)] ^ TABLES4[256 + ((val >> 16) & 0xFF)] ^ TABLES4[(val >> 24) & 0xFF]
        ptr += 4
        remaining -= 4
      end

      # Process remaining bytes
      remaining.times do
        crc = TABLE[(crc ^ ptr.value) & 0xFF] ^ (crc >> 8)
        ptr += 1
      end

      crc
    end

    def self.finalize(crc : UInt32) : UInt32
      crc ^ 0xFFFFFFFF_u32
    end
  end
end
