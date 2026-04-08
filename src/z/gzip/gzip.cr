module Z
  module Gzip
    class Error < Z::Error; end

    MAGIC1 = 0x1F_u8
    MAGIC2 = 0x8B_u8

    CM_DEFLATE = 8_u8

    FTEXT    = 0x01_u8
    FHCRC    = 0x02_u8
    FEXTRA   = 0x04_u8
    FNAME    = 0x08_u8
    FCOMMENT = 0x10_u8
  end
end
