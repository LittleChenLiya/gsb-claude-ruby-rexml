# frozen_string_literal: false

require "tmpdir"

module REXMLTests
  class SerializationCheckTester < Test::Unit::TestCase
    include Helper::Global

    # Builds a small tree holding a legal newline, a legal tab, an
    # already-escaped & entity and (on demand) an illegal control code
    # point in either a text node or an attribute.
    def build_document(illegal: nil)
      document = REXML::Document.new
      root = document.add_element("root")
      note = root.add_element("note", {"a" => "x\ny\tz"})
      note.add_text("line1\nline2")
      raw = root.add_element("raw")
      raw.add_text(REXML::Text.new("already &amp; escaped", false, nil, true))
      case illegal
      when :text
        note.add_text("ok\x08bad")
      when :attribute
        note.attributes.get_attribute("a").normalized = "x\x08y"
      end
      document
    end

    def serialize(document)
      output = +""
      document.write(output)
      output
    end

    class TestLegal < self
      def setup
        @document = build_document
        @output = serialize(@document)
      end

      def test_legal_newline_and_tab_pass_through
        assert_include(@output, "line1\nline2")
        assert_include(@output, "a='x\ny\tz'")
      end

      def test_escaped_entity_is_not_escaped_again
        assert_include(@output, "already &amp; escaped")
        assert_not_include(@output, "&amp;amp;")
      end

      def test_output_parses_again
        reparsed = REXML::Document.new(@output)
        assert_equal("line1\nline2", reparsed.root.elements["note"].text)
        assert_equal("x\ny\tz", reparsed.root.elements["note"].attributes["a"])
        assert_equal("already & escaped", reparsed.root.elements["raw"].text)
      end

      def test_default_formatter_output_is_unchanged
        assert_equal("<root><note a='x\ny\tz'>line1\nline2</note>" \
                     "<raw>already &amp; escaped</raw></root>",
                     @output)
        assert_equal(@output, @document.to_s)
      end
    end

    class TestIllegalText < self
      def setup
        @document = build_document(illegal: :text)
      end

      def test_write_raises_with_path_and_code_point
        output = +""
        exception = assert_raise(RuntimeError) do
          @document.write(output)
        end
        assert_equal("Illegal XML character U+0008 " \
                     "in serialization of /root/note/text()",
                     exception.message)
      end

      def test_write_produces_no_partial_output
        output = +"prefix"
        assert_raise(RuntimeError) do
          @document.write(output)
        end
        assert_equal("prefix", output)
      end

      def test_to_s_raises
        assert_raise(RuntimeError) do
          @document.to_s
        end
      end

      def test_element_write_raises
        suppress_warning do
          assert_raise(RuntimeError) do
            @document.root.write(+"")
          end
        end
      end

      def test_write_to_file_leaves_no_partial_output
        Dir.mktmpdir do |dir|
          path = File.join(dir, "out.xml")
          File.open(path, "w") do |file|
            assert_raise(RuntimeError) do
              @document.write(file)
            end
          end
          assert_equal("", File.read(path))
        end
      end
    end

    class TestIllegalAttribute < self
      def setup
        @document = build_document(illegal: :attribute)
      end

      def test_write_raises_with_path_and_code_point
        output = +""
        exception = assert_raise(RuntimeError) do
          @document.write(output)
        end
        assert_equal("Illegal XML character U+0008 " \
                     "in serialization of /root/note/@a",
                     exception.message)
      end

      def test_write_produces_no_partial_output
        output = +""
        assert_raise(RuntimeError) do
          @document.write(output)
        end
        assert_equal("", output)
      end
    end
  end
end
