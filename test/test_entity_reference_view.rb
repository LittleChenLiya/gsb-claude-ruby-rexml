# frozen_string_literal: false

require_relative "helper"

module REXMLTests
  class EntityReferenceViewTest < Test::Unit::TestCase
    include Helper::Global
    include REXML

    DOCUMENT = <<~XML
      <!DOCTYPE root [
        <!ENTITY declared "declared-value">
      ]>
      <root>a &amp; b &declared; c &#65; &unknown; d</root>
    XML

    def parse
      REXML::Document.new(DOCUMENT)
    end

    def text_node(document)
      document.root.texts.first
    end

    def test_segments_preserve_raw_references_in_order
      text = text_node(parse)
      assert_equal(
        [
          [:text, "a "],
          [:entity, "&amp;"],
          [:text, " b "],
          [:entity, "&declared;"],
          [:text, " c "],
          [:character_reference, "&#65;"],
          [:text, " "],
          [:entity, "&unknown;"],
          [:text, " d"],
        ],
        text.entity_references.map {|segment| [segment[:kind], segment[:source]] }
      )
    end

    def test_predefined_entity
      segment = text_node(parse).entity_references[1]
      assert_equal(:entity, segment[:kind])
      assert_equal("amp", segment[:name])
      assert_equal("&amp;", segment[:source])
      assert_equal("&", segment[:value])
      assert_equal(true, segment[:known])
      assert_nil(segment[:diagnostic])
    end

    def test_internally_declared_entity
      segment = text_node(parse).entity_references[3]
      assert_equal(:entity, segment[:kind])
      assert_equal("declared", segment[:name])
      assert_equal("&declared;", segment[:source])
      assert_equal("declared-value", segment[:value])
      assert_equal(true, segment[:known])
      assert_nil(segment[:diagnostic])
    end

    def test_character_reference
      segment = text_node(parse).entity_references[5]
      assert_equal(:character_reference, segment[:kind])
      assert_equal("&#65;", segment[:source])
      assert_equal("A", segment[:value])
      assert_equal(true, segment[:known])
    end

    def test_unknown_entity_is_preserved_with_diagnostic
      segment = text_node(parse).entity_references[7]
      assert_equal(:entity, segment[:kind])
      assert_equal("unknown", segment[:name])
      assert_equal("&unknown;", segment[:source])
      assert_nil(segment[:value])
      assert_equal(false, segment[:known])
      assert_equal("undefined entity: &unknown;", segment[:diagnostic])
    end

    def test_literal_ampersand_is_distinguished_from_entity_reference
      literal = Text.new("a & b", false, nil, false)
      assert_equal(
        [[:text, "a & b"]],
        literal.entity_references.map {|segment| [segment[:kind], segment[:source]] }
      )

      reference = Text.new("a &amp; b", false, nil, true)
      assert_equal(
        [[:text, "a "], [:entity, "&amp;"], [:text, " b"]],
        reference.entity_references.map {|segment| [segment[:kind], segment[:source]] }
      )
      assert_equal("a & b", reference.value)
    end

    def test_expanded_value_still_uses_existing_reading
      text = text_node(parse)
      assert_equal("a & b declared-value c A &unknown; d", text.value)
    end

    def test_view_does_not_trigger_entity_expansion
      document = parse
      text = text_node(document)
      count_before = document.entity_expansion_count
      text.entity_references
      assert_equal(count_before, document.entity_expansion_count)

      # The existing expanded reading still resolves (and counts)
      # entities as before.
      text.value
      assert_operator(document.entity_expansion_count, :>, count_before)
    end

    def test_mutating_returned_view_does_not_change_document
      document = parse
      text = text_node(document)
      serialized_before = document.to_s

      segments = text.entity_references
      segments.clear
      segments << {kind: :entity, source: "&injected;"}
      assert_raise(FrozenError) do
        text.entity_references[1][:source] = "&injected;"
      end

      assert_equal(serialized_before, document.to_s)
      assert_equal("a & b declared-value c A &unknown; d", text.value)
      assert_equal("&amp;", text.entity_references[1][:source])
    end

    def test_each_call_returns_a_fresh_array
      text = text_node(parse)
      first = text.entity_references
      second = text.entity_references
      assert_not_same(first, second)
      assert_equal(first, second)
    end
  end
end
