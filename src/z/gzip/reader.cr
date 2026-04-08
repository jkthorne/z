module Z
  module Gzip
    class Reader < IO
      include IO::Buffered

      property? sync_close : Bool = false
      getter? closed : Bool = false
      getter header : Header = Header.new

      @deflate_reader : Deflate::Reader?
      @crc32 : UInt32 = CRC32.initial
      @isize : UInt32 = 0_u32
      @finished : Bool = false

      def initialize(@io : IO, @sync_close : Bool = false)
        read_header
        @deflate_reader = Deflate::Reader.new(@io)
      end

      def self.open(io : IO, sync_close : Bool = false, & : Reader ->)
        reader = new(io, sync_close: sync_close)
        begin
          yield reader
        ensure
          reader.close
        end
      end

      def unbuffered_read(slice : Bytes) : Int32
        raise IO::Error.new("Closed stream") if @closed
        return 0 if @finished

        reader = @deflate_reader.not_nil!
        count = reader.read(slice)
        if count > 0
          @crc32 = CRC32.update(slice[0, count], @crc32)
          @isize &+= count.to_u32
        end
        if count == 0
          verify_trailer
          # Check for concatenated gzip members
          if try_read_next_header
            @deflate_reader = Deflate::Reader.new(@io)
            return unbuffered_read(slice)
          else
            @finished = true
          end
        end
        count
      end

      def unbuffered_write(slice : Bytes) : NoReturn
        raise IO::Error.new("Cannot write to a Gzip::Reader")
      end

      def unbuffered_flush : NoReturn
        raise IO::Error.new("Cannot flush a Gzip::Reader")
      end

      def unbuffered_close : Nil
        return if @closed
        @closed = true
        @deflate_reader.try &.close
        @io.close if @sync_close
      end

      def unbuffered_rewind : Nil
        raise IO::Error.new("Cannot rewind a Gzip::Reader")
      end

      private def read_header : Nil
        id1 = @io.read_byte || raise Gzip::Error.new("Unexpected end of gzip header")
        id2 = @io.read_byte || raise Gzip::Error.new("Unexpected end of gzip header")

        unless id1 == MAGIC1 && id2 == MAGIC2
          raise Gzip::Error.new("Invalid gzip magic bytes: #{id1}, #{id2}")
        end

        cm = @io.read_byte || raise Gzip::Error.new("Unexpected end of gzip header")
        unless cm == CM_DEFLATE
          raise Gzip::Error.new("Unsupported compression method: #{cm}")
        end

        flg = @io.read_byte || raise Gzip::Error.new("Unexpected end of gzip header")

        # Read MTIME (4 bytes, little-endian)
        mtime = read_u32_le
        if mtime != 0
          @header.modification_time = Time.unix(mtime.to_i64)
        end

        # XFL and OS
        _xfl = @io.read_byte || raise Gzip::Error.new("Unexpected end of gzip header")
        @header.os = @io.read_byte || raise Gzip::Error.new("Unexpected end of gzip header")

        # FEXTRA
        if flg & FEXTRA != 0
          xlen = read_u16_le.to_i32
          extra = Bytes.new(xlen)
          @io.read_fully(extra)
          @header.extra = extra
        end

        # FNAME
        if flg & FNAME != 0
          @header.name = read_null_terminated_string
        end

        # FCOMMENT
        if flg & FCOMMENT != 0
          @header.comment = read_null_terminated_string
        end

        # FHCRC
        if flg & FHCRC != 0
          _hcrc = read_u16_le  # Skip header CRC16
        end
      end

      private def try_read_next_header : Bool
        id1 = @io.read_byte
        return false if id1.nil?
        id2 = @io.read_byte
        return false if id2.nil?

        if id1 == MAGIC1 && id2 == MAGIC2
          # Reset state for next member
          @crc32 = CRC32.initial
          @isize = 0_u32

          cm = @io.read_byte || return false
          return false unless cm == CM_DEFLATE

          flg = @io.read_byte || return false
          mtime = read_u32_le
          if mtime != 0
            @header.modification_time = Time.unix(mtime.to_i64)
          end
          _xfl = @io.read_byte || return false
          @header.os = @io.read_byte || return false

          if flg & FEXTRA != 0
            xlen = read_u16_le.to_i32
            extra = Bytes.new(xlen)
            @io.read_fully(extra)
            @header.extra = extra
          end
          if flg & FNAME != 0
            @header.name = read_null_terminated_string
          end
          if flg & FCOMMENT != 0
            @header.comment = read_null_terminated_string
          end
          if flg & FHCRC != 0
            _hcrc = read_u16_le
          end

          true
        else
          false
        end
      end

      private def verify_trailer : Nil
        expected_crc = read_u32_le
        expected_isize = read_u32_le

        actual_crc = CRC32.finalize(@crc32)
        unless actual_crc == expected_crc
          raise Gzip::Error.new("CRC-32 mismatch: expected #{expected_crc}, got #{actual_crc}")
        end

        unless @isize == expected_isize
          raise Gzip::Error.new("Size mismatch: expected #{expected_isize}, got #{@isize}")
        end
      end

      private def read_u16_le : UInt16
        b1 = @io.read_byte || raise Gzip::Error.new("Unexpected end of input")
        b2 = @io.read_byte || raise Gzip::Error.new("Unexpected end of input")
        b1.to_u16 | (b2.to_u16 << 8)
      end

      private def read_u32_le : UInt32
        b1 = @io.read_byte || raise Gzip::Error.new("Unexpected end of input")
        b2 = @io.read_byte || raise Gzip::Error.new("Unexpected end of input")
        b3 = @io.read_byte || raise Gzip::Error.new("Unexpected end of input")
        b4 = @io.read_byte || raise Gzip::Error.new("Unexpected end of input")
        b1.to_u32 | (b2.to_u32 << 8) | (b3.to_u32 << 16) | (b4.to_u32 << 24)
      end

      private def read_null_terminated_string : String
        String.build do |sb|
          loop do
            byte = @io.read_byte || raise Gzip::Error.new("Unexpected end of input")
            break if byte == 0
            sb.write_byte(byte)
          end
        end
      end
    end
  end
end
