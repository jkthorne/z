module Z
  module Gzip
    class Writer < IO
      property? sync_close : Bool = false
      getter? closed : Bool = false
      getter header : Header

      @output : IO
      @deflate_writer : Deflate::Writer
      @crc32 : UInt32 = CRC32.initial
      @isize : UInt32 = 0_u32

      @level : Int32

      def initialize(@output : IO, @level : Int32 = Deflate::DEFAULT_COMPRESSION, @header : Header = Header.new, @sync_close : Bool = false)
        write_header
        @deflate_writer = Deflate::Writer.new(@output, level: @level)
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
        @crc32 = CRC32.update(slice, @crc32)
        @isize &+= slice.size.to_u32
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
        raise IO::Error.new("Cannot read from a Gzip::Writer")
      end

      private def write_header : Nil
        @output.write_byte(MAGIC1)
        @output.write_byte(MAGIC2)
        @output.write_byte(CM_DEFLATE)

        flg = 0_u8
        flg |= FNAME if @header.name
        flg |= FCOMMENT if @header.comment
        flg |= FEXTRA if @header.extra
        @output.write_byte(flg)

        # MTIME (4 bytes, little-endian)
        mtime = @header.modification_time.to_unix.to_u32
        write_u32_le(mtime)

        # XFL: 2 = max compression, 4 = fastest (RFC 1952)
        xfl = case @level
              when 9 then 2_u8
              when 1 then 4_u8
              else        0_u8
              end
        @output.write_byte(xfl)
        # OS
        @output.write_byte(@header.os)

        # FEXTRA
        if extra = @header.extra
          write_u16_le(extra.size.to_u16)
          @output.write(extra)
        end

        # FNAME
        if name = @header.name
          @output.write(name.to_slice)
          @output.write_byte(0_u8)
        end

        # FCOMMENT
        if comment = @header.comment
          @output.write(comment.to_slice)
          @output.write_byte(0_u8)
        end
      end

      private def write_trailer : Nil
        write_u32_le(CRC32.finalize(@crc32))
        write_u32_le(@isize)
      end

      private def write_u16_le(value : UInt16) : Nil
        @output.write_byte((value & 0xFF).to_u8)
        @output.write_byte((value >> 8).to_u8)
      end

      private def write_u32_le(value : UInt32) : Nil
        @output.write_byte((value & 0xFF).to_u8)
        @output.write_byte(((value >> 8) & 0xFF).to_u8)
        @output.write_byte(((value >> 16) & 0xFF).to_u8)
        @output.write_byte(((value >> 24) & 0xFF).to_u8)
      end
    end
  end
end
