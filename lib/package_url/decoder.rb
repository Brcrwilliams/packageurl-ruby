# frozen_string_literal: true

require_relative 'string_utils'

require 'uri'

class PackageURL
  class Decoder
    include StringUtils

    def initialize(string)
      @string = string
    end

    def decode!
      decode_subpath!
      decode_qualifiers!
      decode_scheme!
      decode_type!
      decode_version!
      decode_name!
      decode_namespace!

      PackageURL.new(
        type: @type,
        name: @name,
        namespace: @namespace,
        version: @version,
        qualifiers: @qualifiers,
        subpath: @subpath
      )
    end

    private

    def decode_subpath!
      # Split the purl string once from right on '#'
      # Given the string: `scheme:type/namespace/name@version?qualifiers#subpath`
      # - The left side is the remainder: `scheme:type/namespace/name@version?qualifiers`
      # - The right side will be parsed as the subpath: `subpath`
      @subpath, @string = partition(@string, '#', from: :right) do |subpath|
        decode_segments(subpath) do |segment|
          # Discard segments which are blank, `.`, or `..`
          segment.empty? || segment == '.' || segment == '..'
        end
      end
    end

    def decode_qualifiers!
      # Split the remainder once from right on '?'
      # Given string: `scheme:type/namespace/name@version?qualifiers`
      # - The left side is the remainder: `scheme:type/namespace/name@version`
      # - The right side is the qualifiers string: `qualifiers`
      @qualifiers, @string = partition(@string, '?', from: :right) do |qualifiers|
        parse_qualifiers(qualifiers)
      end
    end

    def decode_scheme!
      # Split the remainder once from left on ':'
      # Given the string: `scheme:type/namespace/name@version`
      # - The left side lowercased is the scheme: `scheme`
      # - The right side is the remainder: `type/namespace/name@version`
      @scheme, @string = partition(@string, ':', from: :left)
      raise InvalidPackageURL, 'invalid or missing "pkg:" URL scheme' unless @scheme == 'pkg'
    end

    def decode_type!
      # Strip the remainder from leading and trailing '/'
      @string = strip(@string, '/')
      # Split this once from left on '/'
      # Given the string: `type/namespace/name@version`
      # - The left side lowercased is the type: `type`
      # - The right side is the remainder: `namespace/name@version`
      @type, @string = partition(@string, '/', from: :left)
      raise InvalidPackageURL, 'invalid or missing package type' if @type.empty?
    end

    def decode_version!
      # Split the remainder once from right on '@'
      # Given the string: `namespace/name@version`
      # - The left side is the remainder: `namespace/name`
      # - The right side is the version: `version`
      # - The version must be URI decoded
      @version, @string = partition(@string, '@', from: :right) do |version|
        URI.decode_www_form_component(version)
      end
    end

    def decode_name!
      # Split the remainder once from right on '/'
      # Given the string: `namespace/name`
      # - The left side is the remainder: `namespace`
      # - The right size is the name: `name`
      # - The name must be URI decoded
      @name, @string = partition(@string, '/', from: :right, require_separator: false) do |name|
        URI.decode_www_form_component(name)
      end
    end

    def decode_namespace!
      # If there is anything remaining, this is the namespace.
      # The namespace may contain multiple segments delimited by `/`.
      @namespace = decode_segments(@string, &:empty?) unless @string.empty?
    end

    def decode_segment(segment)
      decoded = URI.decode_www_form_component(segment)

      raise InvalidPackageURL, 'slash-separated segments may not contain `/`' if decoded.include?('/')

      decoded
    end

    def decode_segments(string)
      string.split('/').filter_map do |segment|
        next if block_given? && yield(segment)

        decode_segment(segment)
      end.join('/')
    end

    def parse_qualifiers(raw_qualifiers)
      # - Split the qualifiers on '&'. Each part is a key=value pair
      # - For each pair, split the key=value once from left on '=':
      # - The key is the lowercase left side
      # - The value is the percent-decoded right side
      # - Discard any key/value pairs where the value is empty
      # - If the key is checksums,
      #   split the value on ',' to create a list of checksums
      # - This list of key/value is the qualifiers object
      raw_qualifiers.split('&').each_with_object({}) do |pair, memo|
        key, separator, value = pair.partition('=')

        next if separator.empty?

        key = key.downcase
        value = URI.decode_www_form_component(value)

        next if value.empty?

        memo[key] = case key
                    when 'checksums'
                      value.split(',')
                    else
                      value
                    end
      end
    end
  end
end
