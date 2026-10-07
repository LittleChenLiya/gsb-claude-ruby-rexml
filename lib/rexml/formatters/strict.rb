# frozen_string_literal: false
require_relative 'default'

module REXML
  module Formatters
    # A strict variant of the default formatter.  Before anything is
    # written, it validates the serialized form of every text node and
    # attribute value in the given node (or subtree): if a character that
    # is not a valid XML character (see REXML::Text::VALID_CHAR) would be
    # emitted, a RuntimeError is raised and the output is left completely
    # untouched, so no partial output is ever produced.  The error
    # message reports the XPath of the offending node and the illegal
    # code point.
    #
    # The validation is a pre-check only.  Escaping is still performed by
    # the default formatter, so legal tab and newline characters follow
    # the usual escaping rules of each node category, and already-escaped
    # entities are not escaped again.
    #
    #   formatter = REXML::Formatters::Strict.new
    #   output = +""
    #   formatter.write(document, output)
    class Strict < Default
      # Validates +node+ (and, for containers, its whole subtree) and then
      # writes it with the default formatter.  When validation fails,
      # nothing is written to +output+.
      def write( node, output )
        validate( node )
        super
      end

      private
      # Same as Text::VALID_XML_CHARS but anchored with \A and \z so that
      # a multi-line string cannot slip through a per-line match.
      def valid_xml_chars
        self.class.valid_xml_chars
      end

      def self.valid_xml_chars
        @valid_xml_chars ||= Regexp.new('\A['+
          Text::VALID_CHAR.map { |item|
            case item
            when Integer
              [item].pack('U').force_encoding('utf-8')
            when Range
              [item.first, '-'.ord, item.last].pack('UUU').force_encoding('utf-8')
            end
          }.join +
        ']*\z').freeze
      end
      def validate( node )
        case node
        when Attribute
          check( node.to_s, node )
        when Text
          check( node.to_s, node )
        when Parent
          stack = [node]
          until stack.empty?
            current = stack.pop
            case current
            when Element
              current.attributes.each_attribute do |attribute|
                check( attribute.to_s, attribute )
              end
              stack.concat( current.children.reverse )
            when Parent
              stack.concat( current.children.reverse )
            when Text
              check( current.to_s, current )
            end
          end
        end
      end

      def check( string, node )
        return if valid_xml_chars.match?( string )
        string.each_char do |char|
          code_point = char.ord
          next if Text::VALID_CHAR.any? { |valid| valid === code_point }
          raise "Illegal character U+%04X in %s at %s" %
                [code_point, node.node_type, node.xpath]
        end
      end
    end
  end
end
