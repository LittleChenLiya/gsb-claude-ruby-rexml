# frozen_string_literal: true

require "minitest/autorun"
require "rexml/document"
require "rexml/element_move"

module REXMLTests
  class ElementMoveTest < Minitest::Test
    include REXML

    def test_two_documents_same_prefix_different_uri
      doc_a = Document.new(<<~XML)
        <root xmlns:x="http://a">
          <x:foo x:id="1">hello<x:b/>world</x:foo>
        </root>
      XML
      doc_b = Document.new(<<~XML)
        <root xmlns:x="http://b">
          <sibling>sib</sibling>
          <other/>
        </root>
      XML

      moved = doc_a.root.elements[1]
      target = doc_b.root.elements[1]
      sibling = doc_b.root.elements[1]
      other = doc_b.root.elements[2]

      assert_equal "http://a", moved.namespace("x")
      assert_equal "http://b", sibling.namespace("x")

      moved.move_to(target)

      assert_equal "http://a", moved.namespace("x")
      assert_equal target, moved.parent
      assert_equal doc_b, moved.document

      assert_equal "http://b", sibling.namespace("x")
      assert_equal "http://b", other.namespace("x")
      assert_nil sibling.attributes.get_attribute("xmlns:x")
      assert_nil other.attributes.get_attribute("xmlns:x")

      decl = moved.attributes.get_attribute("xmlns:x")
      refute_nil decl
      assert_equal "http://a", decl.value

      assert_nil doc_a.root.elements[1]
      assert_equal moved, doc_b.root.elements[1].elements[1]
    end

    def test_text_order_unchanged
      doc_a = Document.new(<<~XML)
        <root xmlns:x="http://a">
          <x:foo>first<x:b/>second<x:c/>third</x:foo>
        </root>
      XML
      doc_b = Document.new('<root xmlns:x="http://b"><sibling/></root>')

      moved = doc_a.root.elements[1]
      moved.move_to(doc_b.root.elements[1])

      assert_equal ["first", "second", "third"], moved.texts.map(&:to_s)
      assert_equal [:text, :element, :text, :element, :text],
                   moved.children.map(&:node_type)
    end

    def test_attributes_preserved
      doc_a = Document.new(<<~XML)
        <root xmlns:x="http://a">
          <x:foo x:id="42" plain="v"/>
        </root>
      XML
      doc_b = Document.new('<root xmlns:x="http://b"><sibling/></root>')

      moved = doc_a.root.elements[1]
      moved.move_to(doc_b.root.elements[1])

      attr = moved.attributes.get_attribute("x:id")
      refute_nil attr
      assert_equal "42", attr.value
      assert_equal "http://a", attr.namespace
      assert_equal "v", moved.attributes.get_attribute("plain").value
    end

    def test_ancestor_cycle_rejected
      doc = Document.new("<root><a><b><c/></b></a></root>")
      a = doc.root.elements[1]
      c = a.elements[1].elements[1]

      assert_raises(ElementMove::InvalidMove) { a.move_to(c) }
      assert_equal doc.root, a.parent
      assert_equal "<root><a><b><c/></b></a></root>", doc.to_s
    end

    def test_move_into_self_rejected
      doc = Document.new("<root><a/></root>")
      a = doc.root.elements[1]
      assert_raises(ElementMove::InvalidMove) { a.move_to(a) }
      assert_equal doc.root, a.parent
    end

    def test_unbound_source_prefix_rejected
      doc_a = Document.new("<root/>")
      foo = Element.new("x:foo")
      doc_a.root.add_element(foo)
      doc_b = Document.new('<root xmlns:x="http://b"><sibling/></root>')

      assert_raises(ElementMove::InvalidMove) do
        foo.move_to(doc_b.root.elements[1])
      end
      assert_equal doc_a.root, foo.parent
      assert_equal "<root><x:foo/></root>", doc_a.to_s
      assert_equal "<root xmlns:x='http://b'><sibling/></root>", doc_b.to_s
    end

    def test_move_document_rejected
      doc = Document.new("<root/>")
      assert_raises(ArgumentError) do
        ElementMove.new(doc, Element.new("a"))
      end
    end

    def test_no_conflict_no_declaration
      doc_a = Document.new('<root xmlns:x="http://same"><x:foo/></root>')
      doc_b = Document.new('<root xmlns:x="http://same"><sibling/></root>')

      moved = doc_a.root.elements[1]
      moved.move_to(doc_b.root.elements[1])

      assert_equal "http://same", moved.namespace("x")
      assert_nil moved.attributes.get_attribute("xmlns:x")
    end

    def test_self_declared_prefix_not_redeclared
      doc_a = Document.new('<root><x:foo xmlns:x="http://a"><x:bar/></x:foo></root>')
      doc_b = Document.new('<root xmlns:x="http://b"><sibling/></root>')

      moved = doc_a.root.elements[1]
      moved.move_to(doc_b.root.elements[1])

      assert_equal "http://a", moved.namespace("x")
      assert_equal "http://a", moved.elements[1].namespace("x")
      decls = moved.attributes.to_a.select { |a| a.namespace_declaration? }
      assert_equal 1, decls.size
      assert_equal "http://a", decls[0].value
    end

    def test_descendant_redeclaration_preserved
      doc_a = Document.new(<<~XML)
        <root xmlns:x="http://a">
          <x:foo><x:bar xmlns:x="http://c"/></x:foo>
        </root>
      XML
      doc_b = Document.new('<root xmlns:x="http://b"><sibling/></root>')

      moved = doc_a.root.elements[1]
      moved.move_to(doc_b.root.elements[1])

      assert_equal "http://a", moved.namespace("x")
      assert_equal "http://c", moved.elements[1].namespace("x")
    end

    def test_default_namespace_conflict
      doc_a = Document.new('<root xmlns="http://def-a"><foo/></root>')
      doc_b = Document.new('<root xmlns="http://def-b"><sibling/></root>')

      moved = doc_a.root.elements[1]
      moved.move_to(doc_b.root.elements[1])

      assert_equal "http://def-a", moved.namespace
      assert_equal "http://def-b", doc_b.root.elements[1].namespace
    end

    def test_move_to_own_parent_is_noop
      doc = Document.new("<root><a/></root>")
      a = doc.root.elements[1]
      a.move_to(doc.root)
      assert_equal doc.root, a.parent
      assert_equal "<root><a/></root>", doc.to_s
    end

    def test_move_to_document_root
      doc_a = Document.new('<root xmlns:x="http://a"><x:foo/></root>')
      doc_b = Document.new

      moved = doc_a.root.elements[1]
      moved.move_to(doc_b)

      assert_equal doc_b, moved.parent
      assert_equal "http://a", moved.namespace("x")
      assert_equal "<x:foo xmlns:x='http://a'/>", doc_b.to_s
    end

    def test_add_element_interface_preserved
      doc = Document.new("<root/>")
      doc.root.add_element("a")
      doc.root.add_element(Element.new("b"))
      doc.root.add_element("c", "k" => "v")
      assert_equal "<root><a/><b/><c k='v'/></root>", doc.to_s
    end

    def test_validate_does_not_modify
      doc_a = Document.new('<root xmlns:x="http://a"><x:foo/></root>')
      doc_b = Document.new('<root xmlns:x="http://b"><sibling/></root>')

      moved = doc_a.root.elements[1]
      plan = ElementMove.new(moved, doc_b.root.elements[1])
      plan.validate

      assert_equal doc_a.root, moved.parent
      assert_equal "<root xmlns:x='http://a'><x:foo/></root>", doc_a.to_s
      assert_equal "<root xmlns:x='http://b'><sibling/></root>", doc_b.to_s
    end

    def test_target_document_with_existing_root_rejected
      doc_a = Document.new('<root xmlns:x="http://a"><x:foo/></root>')
      doc_b = Document.new('<existing/>')

      moved = doc_a.root.elements[1]
      assert_raises(ElementMove::InvalidMove) { moved.move_to(doc_b) }
      assert_equal doc_a.root, moved.parent
      assert_equal "existing", doc_b.root.name
    end
  end
end
