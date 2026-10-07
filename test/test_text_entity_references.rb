# frozen_string_literal: false

require_relative "helper"

module REXMLTests
  class TestTextEntityReferences < Test::Unit::TestCase
    MIXED_ENTITIES_XML = <<~XML
      <?xml version="1.0"?>
      <!DOCTYPE root [
        <!ENTITY greeting "Hello">
      ]>
      <root>a &amp; b &greeting; &nosuch; &#65;</root>
    XML

    def parse(xml)
      REXML::Document.new(xml)
    end

    def test_predefined_entities_are_literal_segments
      doc = parse("<root>&lt;&gt;&quot;&apos;&amp;</root>")
      segments = doc.root.get_text.entity_references
      assert_equal([:literal] * 5, segments.map(&:kind))
      assert_equal(["&lt;", "&gt;", "&quot;", "&apos;", "&amp;"],
                   segments.map(&:source))
      assert_equal(["<", ">", "\"", "'", "&"], segments.map(&:to_s))
      # The expanded result still follows the existing readers.
      assert_equal("<>\"'&", doc.root.text)
    end

    def test_character_reference_is_a_literal_segment
      doc = parse("<root>&#65;&#x42;</root>")
      segments = doc.root.get_text.entity_references
      assert_equal([:literal, :literal], segments.map(&:kind))
      assert_equal(["&#65;", "&#x42;"], segments.map(&:source))
      assert_equal(["A", "B"], segments.map(&:to_s))
      assert_equal("AB", doc.root.text)
    end

    def test_internal_declared_entity
      doc = parse(MIXED_ENTITIES_XML)
      segment = doc.root.get_text.entity_references.find(&:entity?)
      assert do
        segment.entity? and
          segment.name == "greeting" and
          segment.resolved? and
          segment.source == "&greeting;" and
          segment.to_s == "&greeting;" # the view never expands
      end
      # The expanded result still follows the existing readers.
      assert_equal("a & b Hello &nosuch; A", doc.root.text)
    end

    def test_unknown_entity_keeps_diagnostic
      doc = parse(MIXED_ENTITIES_XML)
      unknown = doc.root.get_text.entity_references.select(&:entity?).last
      assert do
        unknown.entity? and
          unknown.name == "nosuch" and
          not unknown.resolved? and
          unknown.source == "&nosuch;" and
          unknown.to_s == "&nosuch;"
      end
      # The existing reader keeps the unknown reference as-is, too.
      assert_include(doc.root.text, "&nosuch;")
    end

    def test_literal_ampersand_is_distinguished_from_entities
      doc = parse(MIXED_ENTITIES_XML)
      segments = doc.root.get_text.entity_references
      assert_equal([:literal, :literal, :literal, :entity,
                    :literal, :entity, :literal, :literal],
                   segments.map(&:kind))
      assert_equal(["a ", "&amp;", " b ", "&greeting;",
                    " ", "&nosuch;", " ", "&#65;"],
                   segments.map(&:source))
      assert_equal(["a ", "&", " b ", "&greeting;",
                    " ", "&nosuch;", " ", "A"],
                   segments.map(&:to_s))
      assert_equal([nil, nil, nil, "greeting", nil, "nosuch", nil, nil],
                   segments.map(&:name))
    end

    def test_literal_ampersand_in_constructed_text
      text = REXML::Text.new("Fish & Chips", false, nil, false)
      segments = text.entity_references
      assert_equal([:literal, :literal, :literal], segments.map(&:kind))
      assert_equal(["Fish ", "&amp;", " Chips"], segments.map(&:source))
      assert_equal(["Fish ", "&", " Chips"], segments.map(&:to_s))
    end

    def test_view_does_not_trigger_entity_resolution
      doc = parse(MIXED_ENTITIES_XML)
      text = doc.root.get_text
      assert_equal(0, doc.entity_expansion_count)
      text.entity_references
      assert_equal(0, doc.entity_expansion_count)
      # The existing reader resolves entities as before.
      text.value
      assert_equal(1, doc.entity_expansion_count)
      text.entity_references
      assert_equal(1, doc.entity_expansion_count)
    end

    def test_returned_view_is_detached_from_the_document
      doc = parse(MIXED_ENTITIES_XML)
      text = doc.root.get_text
      before = doc.to_s
      segments = text.entity_references
      assert_not_same(segments, text.entity_references)
      segments.each do |segment|
        assert do
          segment.frozen? and segment.source.frozen? and segment.to_s.frozen?
        end
      end
      segments.clear
      segments << "junk"
      assert_equal(before, doc.to_s)
      assert_equal(8, text.entity_references.size)
    end

    def test_element_entity_references
      doc = parse(<<~XML)
        <!DOCTYPE root [
          <!ENTITY e "v">
        ]>
        <root><a>x &e;</a><b>&amp;</b></root>
      XML
      segments = doc.root.entity_references
      assert_equal([:literal, :entity, :literal], segments.map(&:kind))
      assert_equal(["x ", "&e;", "&amp;"], segments.map(&:source))
      assert_equal([nil, "e", nil], segments.map(&:name))
      assert_equal(0, doc.entity_expansion_count)
    end

    def test_document_entity_references
      doc = parse(MIXED_ENTITIES_XML)
      assert_equal(doc.root.get_text.entity_references,
                   doc.entity_references)
      assert_equal([], REXML::Document.new.entity_references)
    end
  end
end
