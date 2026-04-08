module Z
  module Adler32
    MODULO = 65521_u32
    NMAX   =  5552

    def self.initial : UInt32
      1_u32
    end

    def self.checksum(data : Bytes) : UInt32
      update(data, initial)
    end

    def self.checksum(str : String) : UInt32
      checksum(str.to_slice)
    end

    def self.update(data : Bytes, adler : UInt32) : UInt32
      a = adler & 0xFFFF_u32
      b = (adler >> 16) & 0xFFFF_u32

      offset = 0
      remaining = data.size

      while remaining > 0
        chunk = remaining > NMAX ? NMAX : remaining
        remaining -= chunk

        chunk.times do
          a += data[offset]
          b += a
          offset += 1
        end

        a %= MODULO
        b %= MODULO
      end

      (b << 16) | a
    end
  end
end
