# frozen_string_literal: false
require 'forwardable'

require_relative '../parseexception'
require_relative 'baseparser'
require_relative '../xmltokens'

module REXML
  module Parsers
    # = Using the Pull Parser
    # <em>This API is experimental, and subject to change.</em>
    #  parser = PullParser.new( "<a>text<b att='val'/>txet</a>" )
    #  while parser.has_next?
    #    res = parser.next
    #    puts res[1]['att'] if res.start_tag? and res[0] == 'b'
    #  end
    # See the PullEvent class for information on the content of the results.
    # The data is identical to the arguments passed for the various events to
    # the StreamListener API.
    #
    # Notice that:
    #  parser = PullParser.new( "<a>BAD DOCUMENT" )
    #  while parser.has_next?
    #    res = parser.next
    #    raise res[1] if res.error?
    #  end
    #
    # Nat Price gave me some good ideas for the API.
    class PullParser
      include XMLTokens
      extend Forwardable

      def_delegators( :@parser, :has_next? )
      def_delegators( :@parser, :entity )
      def_delegators( :@parser, :empty? )
      def_delegators( :@parser, :source )

      def initialize stream
        @entities = {}
        @listeners = nil
        @parser = BaseParser.new( stream )
        @my_stack = []
      end

      def add_listener( listener )
        @listeners = [] unless @listeners
        @listeners << listener
      end

      def entity_expansion_count
        @parser.entity_expansion_count
      end

      def entity_expansion_limit=( limit )
        @parser.entity_expansion_limit = limit
      end

      def entity_expansion_text_limit=( limit )
        @parser.entity_expansion_text_limit = limit
      end

      def each
        while has_next?
          yield self.pull
        end
      end

      def peek depth=0
        if @my_stack.length <= depth
          (depth - @my_stack.length + 1).times {
            e = build_event
            @my_stack.push(e)
          }
        end
        @my_stack[depth]
      end

      def pull
        return @my_stack.shift if @my_stack.length > 0

        build_event
      end

      def unshift token
        @my_stack.unshift token
      end

      def reset
        @parser.reset
      end

      private
      def build_event
        event = @parser.pull
        case event[0]
        when :entitydecl
          @entities[ event[1] ] =
            event[2] unless event[2] =~ /PUBLIC|SYSTEM/
        when :text
          unnormalized = @parser.unnormalize( event[1], @entities )
          event << unnormalized
        when :start_element, :end_element
          # Attach an explicit snapshot of the namespace prefix => URI
          # table that is really in effect for this event.  For
          # :start_element the table includes the namespaces declared
          # by the element itself; for :end_element the element's own
          # declarations have already gone out of scope, so the table
          # is the restored outer one.  The snapshot is a private copy
          # taken from the parser's live state (the source text is not
          # re-parsed), so events never share a mutable table with the
          # parser or with each other.
          event << @parser.namespaces
        end
        PullEvent.new( event )
      end
    end

    # A parsing event.  The contents of the event are accessed as an +Array?,
    # and the type is given either by the ...? methods, or by accessing the
    # +type+ accessor.  The contents of this object vary from event to event,
    # but are identical to the arguments passed to +StreamListener+s for each
    # event.
    class PullEvent
      # The type of this event.  Will be one of :tag_start, :tag_end, :text,
      # :processing_instruction, :comment, :doctype, :attlistdecl, :entitydecl,
      # :notationdecl, :entity, :cdata, :xmldecl, or :error.
      def initialize(arg)
        @contents = arg
      end

      def []( start, endd=nil)
        if start.kind_of? Range
          @contents.slice( start.begin+1 .. start.end )
        elsif start.kind_of? Numeric
          if endd.nil?
            @contents.slice( start+1 )
          else
            @contents.slice( start+1, endd )
          end
        else
          raise "Illegal argument #{start.inspect} (#{start.class})"
        end
      end

      def event_type
        @contents[0]
      end

      # For :start_element and :end_element events, returns the
      # snapshot of the namespace prefix => URI mappings in effect for
      # this event (the default namespace, if any, is keyed by "").
      # The original prefixes and their URIs are preserved, and the
      # returned Hash is a private copy that is not shared with the
      # parser or with other events.  Returns nil for other events.
      def namespaces
        case @contents[0]
        when :start_element
          @contents[3]
        when :end_element
          @contents[2]
        end
      end

      # Content: [ String tag_name, Hash attributes, Hash namespaces ]
      def start_element?
        @contents[0] == :start_element
      end

      # Content: [ String tag_name, Hash namespaces ]
      def end_element?
        @contents[0] == :end_element
      end

      # Content: [ String raw_text, String unnormalized_text ]
      def text?
        @contents[0] == :text
      end

      # Content: [ String text ]
      def instruction?
        @contents[0] == :processing_instruction
      end

      # Content: [ String text ]
      def comment?
        @contents[0] == :comment
      end

      # Content: [ String name, String pub_sys, String long_name, String uri ]
      def doctype?
        @contents[0] == :start_doctype
      end

      # Content: [ String text ]
      def attlistdecl?
        @contents[0] == :attlistdecl
      end

      # Content: [ String text ]
      def elementdecl?
        @contents[0] == :elementdecl
      end

      # Due to the wonders of DTDs, an entity declaration can be just about
      # anything.  There's no way to normalize it; you'll have to interpret the
      # content yourself.  However, the following is true:
      #
      # * If the entity declaration is an internal entity:
      #   [ String name, String value ]
      # Content: [ String text ]
      def entitydecl?
        @contents[0] == :entitydecl
      end

      # Content: [ String text ]
      def notationdecl?
        @contents[0] == :notationdecl
      end

      # Content: [ String text ]
      def entity?
        @contents[0] == :entity
      end

      # Content: [ String text ]
      def cdata?
        @contents[0] == :cdata
      end

      # Content: [ String version, String encoding, String standalone ]
      def xmldecl?
        @contents[0] == :xmldecl
      end

      def error?
        @contents[0] == :error
      end

      def inspect
        @contents[0].to_s + ": " + @contents[1..-1].inspect
      end
    end
  end
end
