# frozen_string_literal: true

require 'fastimage'
require 'stringio'

module Onetime
  # Only passive raster formats may be stored or served inline. The MIME is
  # derived from the bytes, never from multipart headers or stored metadata.
  module ImageContent
    RASTER_MIME_TYPES = {
      jpeg: 'image/jpeg',
      png: 'image/png',
      gif: 'image/gif',
      webp: 'image/webp',
      bmp: 'image/bmp',
      tiff: 'image/tiff',
      ico: 'image/x-icon',
    }.freeze

    def self.content_type(bytes)
      RASTER_MIME_TYPES[FastImage.type(StringIO.new(bytes))]
    end
  end
end
