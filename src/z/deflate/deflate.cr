module Z
  module Deflate
    class Error < Z::Error; end

    NO_COMPRESSION      = 0
    BEST_SPEED          = 1
    BEST_COMPRESSION    = 9
    DEFAULT_COMPRESSION = 6

    WINDOW_SIZE = 32768
    WINDOW_MASK = WINDOW_SIZE - 1

    MIN_MATCH = 3
    MAX_MATCH = 258

    MAX_BITS = 15

    END_OF_BLOCK = 256_u16

    enum Strategy
      DEFAULT
      FILTERED
      HUFFMAN_ONLY
      RLE
      FIXED
    end
  end
end
