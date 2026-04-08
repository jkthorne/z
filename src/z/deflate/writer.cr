module Z
  module Deflate
    class Writer < IO
      property? sync_close : Bool = false
      getter? closed : Bool = false

      @output : IO
      @bit_writer : BitWriter
      @block_writer : BlockWriter
      @lz77 : LZ77?
      @level : Int32

      def initialize(@output : IO, @level : Int32 = DEFAULT_COMPRESSION, @sync_close : Bool = false)
        unless (0..9).includes?(@level)
          raise Deflate::Error.new("Compression level must be 0-9, got #{@level}")
        end
        @bit_writer = BitWriter.new(@output)
        @block_writer = BlockWriter.new(@bit_writer, @level)
        @lz77 = @level > 0 ? LZ77.new(@level) : nil
      end

      def self.open(io : IO, level : Int32 = DEFAULT_COMPRESSION, sync_close : Bool = false, & : Writer ->)
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

        if @level == 0
          # Store mode: emit as literals
          slice.each do |byte|
            @block_writer.add_token(Token.new(literal: byte)) { }
          end
        else
          lz77 = @lz77.not_nil!
          lz77.compress(slice) do |token|
            @block_writer.add_token(token) { }
          end
        end
      end

      def flush : Nil
        raise IO::Error.new("Closed stream") if @closed
        if lz77 = @lz77
          lz77.flush do |token|
            @block_writer.add_token(token) { }
          end
        end
        @block_writer.flush_sync
        @bit_writer.flush
      end

      def close : Nil
        return if @closed
        @closed = true

        if lz77 = @lz77
          lz77.flush do |token|
            @block_writer.add_token(token) { }
          end
        end
        @block_writer.write_block(final: true)
        @bit_writer.flush

        @output.close if @sync_close
      end

      def read(slice : Bytes) : NoReturn
        raise IO::Error.new("Cannot read from a Deflate::Writer")
      end
    end
  end
end
