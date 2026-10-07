# frozen_string_literal: false

module REXMLTests
  class StrictFormatterTest < Test::Unit::TestCase
    def format(node)
      formatter = REXML::Formatters::Strict.new
      output = +""
      formatter.write(node, output)
      output
    end

    def format_error(node)
      output = +""
      error = assert_raise(RuntimeError) do
        REXML::Formatters::Strict.new.write(node, output)
      end
      [error, output]
    end

    class ValidTest < self
      def setup
        document = REXML::Document.new
        root = document.add_element("root")
        child = root.add_element("child")
        child.add_attribute("note", "line1\nline2")
        child.add_text("a\tb\nc")
        child.add_text(REXML::Text.new("fish &amp; chips", false, nil, true))
        @document = document
      end

      def test_legal_whitespace_and_escaped_entity_are_written_as_is
        assert_equal("<root><child note='line1\nline2'>a\tb\nc" \
                     "fish &amp; chips</child></root>",
                     format(@document))
      end

      def test_escaped_entity_is_not_escaped_again
        assert_include(format(@document), "fish &amp; chips")
        assert_not_include(format(@document), "&amp;amp;")
      end

      def test_output_can_be_parsed_again
        reparsed = REXML::Document.new(format(@document))
        child = reparsed.root.elements["child"]
        assert_equal("a\tb\ncfish & chips", child.text)
        assert_equal("line1
line2", child.attributes["note"])
      end
    end

    class IllegalTextTest < self
      def test_reports_code_point_and_node_path
        document = REXML::Document.new
        root = document.add_element("root")
        root.add_element("ok").add_text("fine")
        root.add_element("bad").add_text("bad\x01text")
        error, output = format_error(document)
        assert_include(error.message, "U+0001")
        assert_include(error.message, "root/bad/text()")
      end

      def test_no_partial_output
        document = REXML::Document.new
        root = document.add_element("root")
        root.add_element("ok").add_text("fine")
        root.add_element("bad").add_text("bad\x01text")
        _error, output = format_error(document)
        assert_equal("", output)
      end

      def test_illegal_character_after_newline
        element = REXML::Element.new("root")
        element.add_text("line1\nline2\x0B")
        error, _output = format_error(element)
        assert_include(error.message, "U+000B")
      end
    end

    class IllegalAttributeTest < self
      def test_reports_code_point_and_node_path
        document = REXML::Document.new
        root = document.add_element("root")
        bad = root.add_element("bad")
        bad.add_attribute("code", "placeholder")
        bad.attributes.get_attribute("code").normalized = "x\x0By"
        error, output = format_error(document)
        assert_include(error.message, "U+000B")
        assert_include(error.message, "root/bad/@code")
        assert_equal("", output)
      end

      def test_subtree_root_attributes_are_checked
        element = REXML::Element.new("root")
        element.add_attribute("code", "placeholder")
        element.attributes.get_attribute("code").normalized = "\x02"
        error, output = format_error(element)
        assert_include(error.message, "U+0002")
        assert_include(error.message, "root/@code")
        assert_equal("", output)
      end
    end
  end
end
