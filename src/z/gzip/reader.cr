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
        # Track CRC-32 over header bytes for FHCRC verification
        hcrc = CRC32.initial

        id1 = header_read_byte(pointerof(hcrc)) || raise Gzip::Error.new("Unexpected end of gzip header")
        id2 = header_read_byte(pointerof(hcrc)) || raise Gzip::Error.new("Unexpected end of gzip header")

        unless id1 == MAGIC1 && id2 == MAGIC2
          raise Gzip::Error.new("Invalid gzip magic bytes: #{id1}, #{id2}")
        end

        cm = header_read_byte(pointerof(hcrc)) || raise Gzip::Error.new("Unexpected end of gzip header")
        unless cm == CM_DEFLATE
          raise Gzip::Error.new("Unsupported compression method: #{cm}")
        end

        flg = header_read_byte(pointerof(hcrc)) || raise Gzip::Error.new("Unexpected end of gzip header")

        if flg & 0xE0 != 0
          raise Gzip::Error.new("Reserved FLG bits are set")
        end

        # Read MTIME (4 bytes, little-endian)
        mtime = header_read_u32_le(pointerof(hcrc))
        if mtime != 0
          @header.modification_time = Time.unix(mtime.to_i64)
        end

        # XFL and OS
        _xfl = header_read_byte(pointerof(hcrc)) || raise Gzip::Error.new("Unexpected end of gzip header")
        @header.os = header_read_byte(pointerof(hcrc)) || raise Gzip::Error.new("Unexpected end of gzip header")

        # FEXTRA
        if flg & FEXTRA != 0
          xlen = header_read_u16_le(pointerof(hcrc)).to_i32
          extra = Bytes.new(xlen)
          @io.read_fully(extra)
          hcrc = CRC32.update(extra, hcrc)
          @header.extra = extra
        end

        # FNAME
        if flg & FNAME != 0
          @header.name = header_read_null_terminated_string(pointerof(hcrc))
        end

        # FCOMMENT
        if flg & FCOMMENT != 0
          @header.comment = header_read_null_terminated_string(pointerof(hcrc))
        end

        # FHCRC
        if flg & FHCRC != 0
          stored_crc16 = read_u16_le
          expected_crc16 = CRC32.finalize(hcrc) & 0xFFFF_u32
          unless stored_crc16.to_u32 == expected_crc16
            raise Gzip::Error.new("Header CRC16 mismatch: expected #{expected_crc16}, got #{stored_crc16}")
          end
        end
      end

      private def try_read_next_header : Bool
        reader = @deflate_reader.not_nil!
        id1 = reader.read_trailer_byte
        return false if id1.nil?
        id2 = reader.read_trailer_byte
        return false if id2.nil?

        if id1 == MAGIC1 && id2 == MAGIC2
          # Reset state for next member
          @crc32 = CRC32.initial
          @isize = 0_u32

          # Track header CRC from the start (including magic bytes)
          hcrc = CRC32.initial
          hcrc = CRC32.update(Bytes[id1, id2], hcrc)

          cm = header_read_byte(pointerof(hcrc)) || return false
          return false unless cm == CM_DEFLATE

          flg = header_read_byte(pointerof(hcrc)) || return false
          if flg & 0xE0 != 0
            raise Gzip::Error.new("Reserved FLG bits are set")
          end
          mtime = header_read_u32_le(pointerof(hcrc))
          if mtime != 0
            @header.modification_time = Time.unix(mtime.to_i64)
          end
          _xfl = header_read_byte(pointerof(hcrc)) || return false
          @header.os = header_read_byte(pointerof(hcrc)) || return false

          if flg & FEXTRA != 0
            xlen = header_read_u16_le(pointerof(hcrc)).to_i32
            extra = Bytes.new(xlen)
            @io.read_fully(extra)
            hcrc = CRC32.update(extra, hcrc)
            @header.extra = extra
          end
          if flg & FNAME != 0
            @header.name = header_read_null_terminated_string(pointerof(hcrc))
          end
          if flg & FCOMMENT != 0
            @header.comment = header_read_null_terminated_string(pointerof(hcrc))
          end
          if flg & FHCRC != 0
            stored_crc16 = read_u16_le
            expected_crc16 = CRC32.finalize(hcrc) & 0xFFFF_u32
            unless stored_crc16.to_u32 == expected_crc16
              raise Gzip::Error.new("Header CRC16 mismatch: expected #{expected_crc16}, got #{stored_crc16}")
            end
          end

          true
        else
          false
        end
      end

      private def verify_trailer : Nil
        expected_crc = read_u32_le_from_deflate
        expected_isize = read_u32_le_from_deflate

        actual_crc = CRC32.finalize(@crc32)
        unless actual_crc == expected_crc
          raise Gzip::Error.new("CRC-32 mismatch: expected #{expected_crc}, got #{actual_crc}")
        end

        unless @isize == expected_isize
          raise Gzip::Error.new("Size mismatch: expected #{expected_isize}, got #{@isize}")
        end
      end

      # Header reading helpers that accumulate CRC-32 for FHCRC verification
      private def header_read_byte(hcrc : Pointer(UInt32)) : UInt8?
        byte = @io.read_byte
        if byte
          hcrc.value = CRC32.update(Bytes[byte], hcrc.value)
        end
        byte
      end

      private def header_read_u16_le(hcrc : Pointer(UInt32)) : UInt16
        b1 = header_read_byte(hcrc) || raise Gzip::Error.new("Unexpected end of input")
        b2 = header_read_byte(hcrc) || raise Gzip::Error.new("Unexpected end of input")
        b1.to_u16 | (b2.to_u16 << 8)
      end

      private def header_read_u32_le(hcrc : Pointer(UInt32)) : UInt32
        b1 = header_read_byte(hcrc) || raise Gzip::Error.new("Unexpected end of input")
        b2 = header_read_byte(hcrc) || raise Gzip::Error.new("Unexpected end of input")
        b3 = header_read_byte(hcrc) || raise Gzip::Error.new("Unexpected end of input")
        b4 = header_read_byte(hcrc) || raise Gzip::Error.new("Unexpected end of input")
        b1.to_u32 | (b2.to_u32 << 8) | (b3.to_u32 << 16) | (b4.to_u32 << 24)
      end

      private def header_read_null_terminated_string(hcrc : Pointer(UInt32)) : String
        String.build do |sb|
          loop do
            byte = header_read_byte(hcrc) || raise Gzip::Error.new("Unexpected end of input")
            break if byte == 0
            sb.write_byte(byte)
          end
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

      # Read u32 from the deflate reader's buffered stream (for trailer reading)
      private def read_u32_le_from_deflate : UInt32
        reader = @deflate_reader.not_nil!
        b1 = reader.read_trailer_byte || raise Gzip::Error.new("Unexpected end of input")
        b2 = reader.read_trailer_byte || raise Gzip::Error.new("Unexpected end of input")
        b3 = reader.read_trailer_byte || raise Gzip::Error.new("Unexpected end of input")
        b4 = reader.read_trailer_byte || raise Gzip::Error.new("Unexpected end of input")
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
