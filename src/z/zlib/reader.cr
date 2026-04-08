module Z
  module Zlib
    class Reader < IO
      include IO::Buffered

      property? sync_close : Bool = false
      getter? closed : Bool = false

      @deflate_reader : Deflate::Reader
      @adler32 : UInt32 = Adler32.initial

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
        count = @deflate_reader.read(slice)
        if count > 0
          @adler32 = Adler32.update(slice[0, count], @adler32)
        end
        if count == 0
          verify_checksum
        end
        count
      end

      def unbuffered_write(slice : Bytes) : NoReturn
        raise IO::Error.new("Cannot write to a Zlib::Reader")
      end

      def unbuffered_flush : NoReturn
        raise IO::Error.new("Cannot flush a Zlib::Reader")
      end

      def unbuffered_close : Nil
        return if @closed
        @closed = true
        @deflate_reader.close
        @io.close if @sync_close
      end

      def unbuffered_rewind : Nil
        raise IO::Error.new("Cannot rewind a Zlib::Reader")
      end

      private def read_header : Nil
        cmf = @io.read_byte || raise Zlib::Error.new("Unexpected end of zlib header")
        flg = @io.read_byte || raise Zlib::Error.new("Unexpected end of zlib header")

        if (cmf.to_u16 * 256 + flg.to_u16) % 31 != 0
          raise Zlib::Error.new("Invalid zlib header checksum")
        end

        cm = cmf & 0x0F
        unless cm == CM_DEFLATE
          raise Zlib::Error.new("Unsupported compression method: #{cm}")
        end

        cinfo = (cmf >> 4) & 0x0F
        if cinfo > 7
          raise Zlib::Error.new("Invalid window size: #{cinfo}")
        end

        fdict = (flg >> 5) & 1
        if fdict == 1
          raise Zlib::Error.new("Preset dictionaries not yet supported")
        end
      end

      @checksum_verified = false

      private def verify_checksum : Nil
        return if @checksum_verified
        @checksum_verified = true

        # Read Adler-32 checksum (big-endian) from deflate reader's buffered stream
        b1 = @deflate_reader.read_trailer_byte || raise Zlib::Error.new("Truncated zlib stream: missing Adler-32 checksum")
        b2 = @deflate_reader.read_trailer_byte || raise Zlib::Error.new("Truncated zlib stream: missing Adler-32 checksum")
        b3 = @deflate_reader.read_trailer_byte || raise Zlib::Error.new("Truncated zlib stream: missing Adler-32 checksum")
        b4 = @deflate_reader.read_trailer_byte || raise Zlib::Error.new("Truncated zlib stream: missing Adler-32 checksum")

        expected = (b1.to_u32 << 24) | (b2.to_u32 << 16) | (b3.to_u32 << 8) | b4.to_u32
        unless @adler32 == expected
          raise Zlib::Error.new("Adler-32 checksum mismatch: expected #{expected}, got #{@adler32}")
        end
      end
    end
  end
end
