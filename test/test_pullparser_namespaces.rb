# frozen_string_literal: false
#
# Namespace snapshot tests for the pull parser, written for Minitest.
#
# Run with:
#   ruby -Ilib test/test_pullparser_namespaces.rb
# (or, from a checkout with the gem installed:)
#   ruby -Ilib -rminitest/autorun test/test_pullparser_namespaces.rb

require "minitest/autorun"
require "rexml/parsers/pullparser"

module REXMLTests
  class PullParserNamespacesTest < Minitest::Test
    XML_NS = "http://www.w3.org/XML/1998/namespace"

    # A three-level document: the inner level rebinds the prefix "p"
    # and the outer level declares a default namespace.
    THREE_LEVEL_XML = <<~XML
      <root xmlns="http://example.org/default" xmlns:p="http://example.org/outer">
        <p:middle xmlns:p="http://example.org/inner" plain="0">
          <p:leaf p:attr="1" free="2"/>
        </p:middle>
      </root>
    XML

    def pull_events(source)
      parser = REXML::Parsers::PullParser.new(source)
      events = []
      events << parser.pull while parser.has_next?
      events
    end

    def element_events(source = THREE_LEVEL_XML)
      pull_events(source).select { |event| event.start_element? or event.end_element? }
    end

    def test_start_and_end_events_carry_effective_prefix_table
      events = element_events
      sequence = events.map { |event| [event.event_type, event[0], event.namespaces] }

      root_start, middle_start, leaf_start, leaf_end, middle_end, root_end =
        sequence

      assert_equal([:start_element, "root"], root_start[0..1])
      assert_equal("http://example.org/default", root_start[2][""])
      assert_equal("http://example.org/outer", root_start[2]["p"])
      assert_equal(XML_NS, root_start[2]["xml"])

      # Inner level rebinds p; the original prefix and new URI are kept.
      assert_equal([:start_element, "p:middle"], middle_start[0..1])
      assert_equal("http://example.org/inner", middle_start[2]["p"])
      assert_equal("http://example.org/default", middle_start[2][""])

      assert_equal([:start_element, "p:leaf"], leaf_start[0..1])
      assert_equal("http://example.org/inner", leaf_start[2]["p"])

      # The empty element adds no bindings, so its end sees the same
      # (middle) table.
      assert_equal([:end_element, "p:leaf"], leaf_end[0..1])
      assert_equal("http://example.org/inner", leaf_end[2]["p"])

      # After the inner rebinding ends, the end event is back to the
      # outer URI.
      assert_equal([:end_element, "p:middle"], middle_end[0..1])
      assert_equal("http://example.org/outer", middle_end[2]["p"])
      assert_equal("http://example.org/default", middle_end[2][""])

      # After the root ends, only the built-in xml binding remains.
      assert_equal([:end_element, "root"], root_end[0..1])
      assert_equal({"xml" => XML_NS}, root_end[2])
    end

    def test_inner_rebinding_is_restored_after_end_tag
      # A prefix bound only inside an element must not leak to
      # following siblings.
      assert_raises(REXML::UndefinedNamespaceException) do
        pull_events(%{<a xmlns:p="http://example.org/inner"><b/></a><p:c/>})
      end
    end

    def test_default_namespace_is_not_applied_to_unprefixed_attributes
      events = element_events
      middle = events.find { |event| event.start_element? and event[0] == "p:middle" }
      leaf = events.find { |event| event.start_element? and event[0] == "p:leaf" }

      # Attributes are reported with their raw names; the in-scope
      # default namespace ("" => ...) is never bound to them.
      assert_equal("0", middle[1]["plain"])
      assert_equal("http://example.org/inner", middle[1]["xmlns:p"])
      assert_equal("1", leaf[1]["p:attr"])
      assert_equal("2", leaf[1]["free"])
      refute(middle[1].key?("xmlns"))

      # If the default namespace were wrongly applied to attributes,
      # the unprefixed "code" below would collide with "p:code".
      source = %{<e xmlns="http://example.org/d" xmlns:p="http://example.org/d" } +
               %{code="1" p:code="2"/>}
      attributes = nil
      pull_events(source).each do |event|
        attributes = event[1] if event.start_element?
      end
      assert_equal("1", attributes["code"])
      assert_equal("2", attributes["p:code"])
    end

    def test_undeclared_prefix_is_rejected_with_position
      error = assert_raises(REXML::UndefinedNamespaceException) do
        pull_events("<root>\n  <q:child/>\n</root>")
      end
      assert_match(/Undefined prefix q found/, error.message)
      assert_equal(2, error.line)
      assert_kind_of(Integer, error.position)
      assert_match(/Line: 2/, error.to_s)
      assert_match(/Position: \d+/, error.to_s)
    end

    def test_empty_default_binding_undeclares_default_namespace
      source = %{<a xmlns="http://example.org/u"><b xmlns=""><c/></b></a>}
      events = element_events(source)
      by_tag = {}
      events.each { |event| by_tag[[event.event_type, event[0]]] = event.namespaces }

      assert_equal("http://example.org/u", by_tag[[:start_element, "a"]][""])
      # xmlns="" removes the default namespace within <b>, per the XML
      # namespace rules.
      refute(by_tag[[:start_element, "b"]].key?(""))
      refute(by_tag[[:start_element, "c"]].key?(""))
      # Leaving <b> restores the outer default namespace.
      assert_equal("http://example.org/u", by_tag[[:end_element, "b"]][""])
      refute(by_tag[[:end_element, "a"]].key?(""))
    end

    def test_empty_prefixed_binding_is_rejected
      error = assert_raises(REXML::ParseException) do
        pull_events(%{<a xmlns:p=""/>})
      end
      assert_match(/must not be empty/, error.message)
    end

    def test_events_do_not_share_mutable_namespace_tables
      events = element_events
      starts = events.select { |event| event.start_element? }

      # Each event owns its snapshot.
      assert(starts.combination(2).all? { |a, b| !a.namespaces.equal?(b.namespaces) })

      # Mutating one snapshot affects neither the parser nor other events.
      root_start = starts.first
      root_start.namespaces["p"] = "http://example.org/hacked"
      middle_start = starts[1]
      assert_equal("http://example.org/inner", middle_start.namespaces["p"])
    end

    def test_parsers_do_not_share_mutable_namespace_tables
      parser1 = REXML::Parsers::PullParser.new(
        %{<a xmlns:p="http://example.org/one"><p:b/></a>})
      parser2 = REXML::Parsers::PullParser.new(
        %{<a xmlns:p="http://example.org/two"><p:b/></a>})

      start1 = parser1.pull
      start2 = parser2.pull
      assert_equal("http://example.org/one", start1.namespaces["p"])
      assert_equal("http://example.org/two", start2.namespaces["p"])
      refute(start1.namespaces.equal?(start2.namespaces))

      start1.namespaces["p"] = "http://example.org/hacked"
      assert_equal("http://example.org/two", start2.namespaces["p"])

      # Draining parser1 must not disturb the snapshot parser2 took.
      parser1.pull while parser1.has_next?
      assert_equal("http://example.org/two", start2.namespaces["p"])
    end
  end
end
