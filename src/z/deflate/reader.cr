module Z
  module Deflate
    class Reader < IO
      include IO::Buffered

      property? sync_close : Bool = false
      getter? closed : Bool = false

      @inflater : Inflater

      def initialize(@io : IO, @sync_close : Bool = false)
        @inflater = Inflater.new(@io)
      end

      # Read a byte from the post-deflate stream (drains buffered bytes first)
      def read_trailer_byte : UInt8?
        @inflater.bit_reader.read_trailer_byte
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
        @inflater.read(slice)
      end

      def unbuffered_write(slice : Bytes) : NoReturn
        raise IO::Error.new("Cannot write to a Deflate::Reader")
      end

      def unbuffered_flush : NoReturn
        raise IO::Error.new("Cannot flush a Deflate::Reader")
      end

      def unbuffered_close : Nil
        return if @closed
        @closed = true
        @io.close if @sync_close
      end

      def unbuffered_rewind : Nil
        raise IO::Error.new("Cannot rewind a Deflate::Reader")
      end
    end
  end
end
