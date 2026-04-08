module Z
  module Zlib
    class Writer < IO
      property? sync_close : Bool = false
      getter? closed : Bool = false

      @output : IO
      @deflate_writer : Deflate::Writer
      @adler32 : UInt32 = Adler32.initial

      def initialize(@output : IO, level : Int32 = Deflate::DEFAULT_COMPRESSION, @sync_close : Bool = false)
        write_header(level)
        @deflate_writer = Deflate::Writer.new(@output, level: level)
      end

      def self.open(io : IO, level : Int32 = Deflate::DEFAULT_COMPRESSION, sync_close : Bool = false, & : Writer ->)
        writer = new(io, level: level, sync_close: sync_close)
        begin
          yield writer
        ensure
          writer.close
        end
      end

      def write(slice : Bytes) : Nil
        raise IO::Error.new("Closed stream") if @closed
        return if slice.empty?
        @adler32 = Adler32.update(slice, @adler32)
        @deflate_writer.write(slice)
      end

      def flush : Nil
        raise IO::Error.new("Closed stream") if @closed
        @deflate_writer.flush
      end

      def close : Nil
        return if @closed
        @closed = true
        @deflate_writer.close
        write_trailer
        @output.close if @sync_close
      end

      def read(slice : Bytes) : NoReturn
        raise IO::Error.new("Cannot read from a Zlib::Writer")
      end

      private def write_header(level : Int32) : Nil
        # CMF byte: CM=8 (deflate), CINFO=7 (32K window)
        cmf = (7_u8 << 4) | 8_u8  # 0x78

        # FLG byte: FLEVEL based on compression level, no FDICT
        flevel = case level
                 when 0, 1 then 0_u8  # fastest
                 when 2..5  then 1_u8  # fast
                 when 6     then 2_u8  # default
                 else            3_u8  # maximum
                 end
        flg = flevel << 6

        # Adjust FLG so (CMF * 256 + FLG) % 31 == 0
        check = (cmf.to_u16 * 256 + flg.to_u16) % 31
        if check != 0
          flg += (31 - check).to_u8
        end

        @output.write_byte(cmf)
        @output.write_byte(flg)
      end

      private def write_trailer : Nil
        # Adler-32 in big-endian
        @output.write_byte(((@adler32 >> 24) & 0xFF).to_u8)
        @output.write_byte(((@adler32 >> 16) & 0xFF).to_u8)
        @output.write_byte(((@adler32 >> 8) & 0xFF).to_u8)
        @output.write_byte((@adler32 & 0xFF).to_u8)
      end
    end
  end
end
