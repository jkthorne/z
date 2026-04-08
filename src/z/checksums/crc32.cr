module Z
  module CRC32
    POLYNOMIAL = 0xEDB88320_u32

    TABLE = begin
      table = StaticArray(UInt32, 256).new(0_u32)
      256.times do |i|
        crc = i.to_u32
        8.times do
          if crc & 1 == 1
            crc = (crc >> 1) ^ POLYNOMIAL
          else
            crc >>= 1
          end
        end
        table[i] = crc
      end
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
      data.each do |byte|
        crc = TABLE[(crc ^ byte) & 0xFF] ^ (crc >> 8)
      end
      crc
    end

    def self.finalize(crc : UInt32) : UInt32
      crc ^ 0xFFFFFFFF_u32
    end
  end
end
