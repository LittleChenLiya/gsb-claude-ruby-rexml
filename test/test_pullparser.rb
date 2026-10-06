# frozen_string_literal: false

require 'rexml/parsers/pullparser'

module REXMLTests
  class PullParserTester < Test::Unit::TestCase
    include REXML
    def test_basics
      source = '<?xml version="1.0"?>
      <!DOCTYPE blah>
      <a>foo &lt;<b attribute="value">bar</b> nooo</a>'
      parser = REXML::Parsers::PullParser.new(source)
      res = { :text=>0 }
      until parser.empty?
        results = parser.pull
        res[ :xmldecl ] = true if results.xmldecl?
        res[ :doctype ] = true if results.doctype?
        res[ :a ] = true if results.start_element? and results[0] == 'a'
        if results.start_element? and results[0] == 'b'
          res[ :b ] = true
          assert_equal 'value', results[1]['attribute']
        end
        res[ :text ] += 1 if results.text?
      end
      [ :xmldecl, :doctype, :a, :b ].each { |tag|
        assert res[tag] , "#{tag} wasn't processed"
      }
      assert_equal 4, res[ :text ]
    rescue ParseException
      puts $!
    end

    def test_bad_document
      source = "<a><b></a>"
      parser = REXML::Parsers::PullParser.new(source)
      assert_raise(ParseException, "Parsing should have failed") {
        parser.pull while parser.has_next?
      }
    end

    def test_entity_replacement
      source = '<!DOCTYPE foo [
      <!ENTITY la "1234">
      <!ENTITY lala "--&la;--">
      <!ENTITY lalal "&la;&la;">
      ]><a><la>&la;</la><lala>&lala;</lala></a>'
      pp = REXML::Parsers::PullParser.new( source )
      el_name = ''
      while pp.has_next?
        event = pp.pull
        case event.event_type
        when :start_element
          el_name = event[0]
        when :text
          case el_name
          when 'la'
            assert_equal('1234', event[1])
          when 'lala'
            assert_equal('--1234--', event[1])
          end
        end
      end
    end

    def test_character_references
      source = '<root><a>&#65;</a><b>&#x42;</b></root>'
      parser = REXML::Parsers::PullParser.new( source )

      events = {}
      element_name = ''
      while parser.has_next?
        event = parser.pull
        case event.event_type
        when :start_element
          element_name = event[0]
        when :text
          events[element_name] = event[1]
        end
      end

      assert_equal('A', events['a'])
      assert_equal("B", events['b'])
    end

    def test_text_entity_references
      source = '<root><a>&lt;P&gt; &lt;I&gt; &lt;B&gt; Text &lt;/B&gt;  &lt;/I&gt;</a></root>'
      parser = REXML::Parsers::PullParser.new( source )

      events = []
      while parser.has_next?
        event = parser.pull
        case event.event_type
        when :text
          events << event[1]
        end
      end

      assert_equal(["<P> <I> <B> Text </B>  </I>"], events)
    end

    def test_text_content_with_line_breaks
      source = "<root><a>A</a><b>B\n</b><c>C\r\n</c></root>"
      parser = REXML::Parsers::PullParser.new( source )

      events = {}
      element_name = ''
      while parser.has_next?
        event = parser.pull
        case event.event_type
        when :start_element
          element_name = event[0]
        when :text
          events[element_name] = event[1]
        end
      end

      assert_equal('A', events['a'])
      assert_equal("B\n", events['b'])
      assert_equal("C\n", events['c'])
    end

    def test_peek_unshift
      source = "<a><b/></a>"
      REXML::Parsers::PullParser.new(source)
      # FINISH ME!
    end

    def test_inspect
      xml =  '<a id="1"><b id="2">Hey</b></a>'
      parser = Parsers::PullParser.new( xml )
      while parser.has_next?
        pull_event = parser.pull
        if pull_event.start_element?
          peek = parser.peek()
          peek.inspect
        end
      end
    end

    def test_peek
      xml =  '<a id="1"><b id="2">Hey</b></a>'
      parser = Parsers::PullParser.new( xml )
      names = %w{ a b }
      while parser.has_next?
        pull_event = parser.pull
        if pull_event.start_element?
          assert_equal( :start_element, pull_event.event_type )
          assert_equal( names.shift, pull_event[0] )
          if names[0] == 'b'
            peek = parser.peek()
            assert_equal( :start_element, peek.event_type )
            assert_equal( names[0], peek[0] )
          end
        end
      end
      assert_equal( 0, names.length )
    end

    def test_reset
      xml_chunks = [
        "<message>First valid and complete message</message>",
        "<message>Second valid and complete message</message>",
        "<message>Third valid and complete message</message>"
      ]

      messages = []

      IO.pipe do |reader, writer|
        xml_chunks.each do |chunk|
          writer.write(chunk)
        end
        writer.close

        parser = REXML::Parsers::PullParser.new(reader)
        while parser.has_next?
          parser.pull
          message_text = parser.pull
          messages << message_text[0]
          parser.pull
          parser.reset
        end
      end

      assert_equal(
        messages,
        ["First valid and complete message",
         "Second valid and complete message",
         "Third valid and complete message"]
      )
    end

    class NamespaceTest < Test::Unit::TestCase
      # Three-level XML: root > mid > leaf, plus a sibling of mid.
      # The "p" prefix is rebound at the middle level, and a default
      # namespace is declared at the root.
      THREE_LEVEL_XML = <<-XML
<root xmlns:p="outer" xmlns="default0">
  <mid xmlns:p="middle">
    <leaf p:a="1" plain="2"/>
  </mid>
  <sibling p:b="3"/>
</root>
      XML

      XML_NAMESPACE = "http://www.w3.org/XML/1998/namespace"

      def collect_element_events(xml)
        parser = REXML::Parsers::PullParser.new(xml)
        events = []
        while parser.has_next?
          event = parser.pull
          next unless event.start_element? or event.end_element?
          events << event
        end
        events
      end

      def test_start_and_end_events_carry_effective_namespaces
        events = collect_element_events(THREE_LEVEL_XML)
        snapshots = events.map {|event| [event.event_type, event[0], event.namespaces]}

        root_start, mid_start, leaf_start, leaf_end, mid_end,
          sibling_start, sibling_end, root_end = snapshots

        # Each start event sees the table really in effect, including
        # the declarations made by the element itself.
        assert_equal(:start_element, root_start[0])
        assert_equal("outer", root_start[2]["p"])
        assert_equal("default0", root_start[2][""])
        assert_equal(XML_NAMESPACE, root_start[2]["xml"])

        # Inner rebinding: mid and its descendants see the inner URI.
        assert_equal("middle", mid_start[2]["p"])
        assert_equal("middle", leaf_start[2]["p"])

        # An end event still sees the scope of the element being closed.
        assert_equal([:end_element, "leaf"], leaf_end[0, 2])
        assert_equal("middle", leaf_end[2]["p"])
        assert_equal([:end_element, "mid"], mid_end[0, 2])
        assert_equal("middle", mid_end[2]["p"])

        # Exiting the element restores the outer binding: the sibling
        # (and its prefixed attribute) use the outer URI again.
        assert_equal([:start_element, "sibling"], sibling_start[0, 2])
        assert_equal("outer", sibling_start[2]["p"])
        assert_equal("outer", sibling_end[2]["p"])
        assert_equal("outer", root_end[2]["p"])
      end

      def test_keeps_uri_and_original_prefix
        events = collect_element_events(THREE_LEVEL_XML)
        leaf = events.find {|event| event.start_element? and event[0] == "leaf"}
        # The attributes keep their original prefixed names...
        assert_equal(["p:a", "plain"], leaf[1].keys)
        # ...and the snapshot keeps the original prefix => URI mapping.
        assert_equal("middle", leaf.namespaces["p"])
        assert_equal("middle", leaf.attribute_namespaces["p:a"])
        sibling = events.find {|event| event.start_element? and event[0] == "sibling"}
        assert_equal("outer", sibling.attribute_namespaces["p:b"])
      end

      def test_default_namespace_does_not_apply_to_attributes
        events = collect_element_events(THREE_LEVEL_XML)
        leaf = events.find {|event| event.start_element? and event[0] == "leaf"}
        # The default namespace applies to the element itself...
        assert_equal("default0", leaf.namespace)
        # ...but never to attributes: an unprefixed attribute has no
        # namespace even while a default namespace is in scope.
        assert_nil(leaf.attribute_namespaces["plain"])
        assert(leaf.attribute_namespaces.key?("plain"))
        # Namespace declarations themselves have no namespace either.
        root = events.find {|event| event.start_element? and event[0] == "root"}
        assert_nil(root.attribute_namespaces["xmlns"])
        assert_nil(root.attribute_namespaces["xmlns:p"])
      end

      def test_inner_rebinding_does_not_leak_to_siblings
        xml = '<root><a xmlns:q="inner-uri"/><b q:x="1"/></root>'
        parser = REXML::Parsers::PullParser.new(xml)
        assert_raise(REXML::UndefinedNamespaceException) do
          parser.pull while parser.has_next?
        end
      end

      def test_undeclared_prefix_is_rejected_with_position
        xml = "<root>\n  <a>\n    <b q:x=\"1\"/>\n  </a>\n</root>"
        parser = REXML::Parsers::PullParser.new(xml)
        exception = assert_raise(REXML::UndefinedNamespaceException) do
          parser.pull while parser.has_next?
        end
        assert_match(/\AUndefined prefix q found/, exception.message)
        # The position is reported from the parser's current state,
        # without re-parsing the original text.
        assert_equal(3, exception.line)
        assert_equal(29, exception.position)
        assert_match(/^Line: 3$/, exception.to_s)
        assert_match(/^Position: 29$/, exception.to_s)
      end

      def test_empty_default_namespace_binding_unbinds
        xml = '<root xmlns="d"><child xmlns=""><leaf/></child></root>'
        events = collect_element_events(xml)
        root, child, leaf, = events.select(&:start_element?)
        assert_equal("d", root.namespaces[""])
        # xmlns="" removes the default namespace in the inner scope...
        assert_false(child.namespaces.key?(""))
        assert_false(leaf.namespaces.key?(""))
        assert_nil(child.namespace)
        assert_nil(leaf.namespace)
        # ...and the outer default namespace is restored afterwards.
        root_end = events.reverse.find {|event| event.end_element?}
        assert_equal("d", root_end.namespaces[""])
      end

      def test_empty_prefixed_binding_is_rejected
        # XML Namespaces 1.0: a prefix must not be bound to an empty URI.
        parser = REXML::Parsers::PullParser.new('<root xmlns:p=""/>')
        exception = assert_raise(REXML::ParseException) do
          parser.pull while parser.has_next?
        end
        assert_match(/must not be empty/, exception.message)
      end

      def test_parsers_do_not_share_mutable_namespace_tables
        xml = '<r xmlns:p="u1"><a/></r>'
        parsers = 2.times.map { REXML::Parsers::PullParser.new(xml) }
        firsts = parsers.map do |parser|
          event = nil
          event = parser.pull until event and event.start_element?
          event
        end
        assert_false(firsts[0].namespaces.equal?(firsts[1].namespaces))

        firsts[0].namespaces["p"] = "HACKED"
        firsts[0].namespaces["evil"] = "HACKED"
        # The other parser's snapshot is unaffected...
        assert_equal("u1", firsts[1].namespaces["p"])
        assert_false(firsts[1].namespaces.key?("evil"))
        # ...and so are later snapshots of the same parser.
        event = nil
        event = parsers[0].pull until event and event.start_element?
        assert_equal("u1", event.namespaces["p"])
        assert_false(event.namespaces.key?("evil"))
      end

      def test_peek_carries_namespaces
        parser = REXML::Parsers::PullParser.new('<a xmlns:p="u"><b/></a>')
        event = nil
        event = parser.pull until event and event.start_element?
        peeked = parser.peek
        assert(peeked.start_element?)
        assert_equal("u", peeked.namespaces["p"])
      end
    end

    class EntityExpansionLimitTest < Test::Unit::TestCase
      class GeneralEntityTest < self
        def test_have_value
          source = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE member [
  <!ENTITY a "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">
  <!ENTITY b "&c;&c;&c;&c;&c;&c;&c;&c;&c;&c;">
  <!ENTITY c "&d;&d;&d;&d;&d;&d;&d;&d;&d;&d;">
  <!ENTITY d "&e;&e;&e;&e;&e;&e;&e;&e;&e;&e;">
  <!ENTITY e "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx">
]>
<member>
&a;
</member>
          XML

          parser = REXML::Parsers::PullParser.new(source)
          assert_raise(RuntimeError.new("entity expansion has grown too large")) do
            while parser.has_next?
              parser.pull
            end
          end
        end

        def test_empty_value
          source = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE member [
  <!ENTITY a "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">
  <!ENTITY b "&c;&c;&c;&c;&c;&c;&c;&c;&c;&c;">
  <!ENTITY c "&d;&d;&d;&d;&d;&d;&d;&d;&d;&d;">
  <!ENTITY d "&e;&e;&e;&e;&e;&e;&e;&e;&e;&e;">
  <!ENTITY e "">
]>
<member>
&a;
</member>
          XML

          parser = REXML::Parsers::PullParser.new(source)
          parser.entity_expansion_limit = 100000
          while parser.has_next?
            parser.pull
          end
          assert_equal(11111, parser.entity_expansion_count)

          parser = REXML::Parsers::PullParser.new(source)
          assert_raise(RuntimeError.new("number of entity expansions exceeded, processing aborted.")) do
            while parser.has_next?
              parser.pull
            end
          end
          assert do
            parser.entity_expansion_count > REXML::Security.entity_expansion_limit
          end
        end

        def test_with_default_entity
          source = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE member [
  <!ENTITY a "a">
  <!ENTITY a2 "&a; &a;">
]>
<member>
&a;
&a2;
&lt;
</member>
          XML

          parser = REXML::Parsers::PullParser.new(source)
          parser.entity_expansion_limit = 4
          while parser.has_next?
            parser.pull
          end

          parser = REXML::Parsers::PullParser.new(source)
          parser.entity_expansion_limit = 3
          assert_raise(RuntimeError.new("number of entity expansions exceeded, processing aborted.")) do
            while parser.has_next?
              parser.pull
            end
          end
        end

        def test_with_only_default_entities
          member_value = "&lt;p&gt;#{'A' * REXML::Security.entity_expansion_text_limit}&lt;/p&gt;"
          source = <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<member>
#{member_value}
</member>
          XML

          parser = REXML::Parsers::PullParser.new(source)
          events = {}
          element_name = ''
          while parser.has_next?
            event = parser.pull
            case event.event_type
            when :start_element
              element_name = event[0]
            when :text
              events[element_name] = event[1]
            end
          end

          expected_value = "<p>#{'A' * REXML::Security.entity_expansion_text_limit}</p>"
          assert_equal(expected_value, events['member'].strip)
          assert_equal(0, parser.entity_expansion_count)
          assert do
            events['member'].bytesize > REXML::Security.entity_expansion_text_limit
          end
        end

        def test_entity_expansion_text_limit
          source = <<-XML
<!DOCTYPE member [
  <!ENTITY a "&b;&b;&b;">
  <!ENTITY b "&c;&d;&e;">
  <!ENTITY c "xxxxxxxxxx">
  <!ENTITY d "yyyyyyyyyy">
  <!ENTITY e "zzzzzzzzzz">
]>
<member>&a;</member>
          XML

          parser = REXML::Parsers::PullParser.new(source)
          parser.entity_expansion_text_limit = 90
          events = {}
          element_name = ''
          while parser.has_next?
            event = parser.pull
            case event.event_type
            when :start_element
              element_name = event[0]
            when :text
              events[element_name] = event[1]
            end
          end
          assert_equal(90, events['member'].size)
        end
      end
    end
  end
end
