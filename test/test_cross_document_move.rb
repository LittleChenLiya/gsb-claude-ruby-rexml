# frozen_string_literal: false
require_relative "helper"

module REXMLTests
  # Tests for REXML::MovePlan: explicit, validated cross-Document moves.
  #
  # Run with:
  #   ruby -Ilib -Itest test/test_cross_document_move.rb
  class TestCrossDocumentMove < Test::Unit::TestCase
    include REXML

    # Two documents bind the same prefix "n" to different URIs.  After
    # the move the moved subtree must still resolve "n" to its original
    # URI, via a declaration added on the moved element itself.
    def test_same_prefix_different_uri_keeps_original_uri
      source = Document.new(
        %(<s xmlns:n="urn:source"><n:x n:a="1">hello</n:x></s>))
      target = Document.new(
        %(<t xmlns:n="urn:target"><n:y/></t>))
      node = source.root.elements[1]

      plan = MovePlan.new(node, target.root)
      assert_true(plan.valid?)
      plan.execute!

      moved = target.root.elements[2]
      assert_same(node, moved) # node identity is preserved
      assert_equal("urn:source", moved.namespace("n"))
      assert_equal("urn:source",
                   moved.attributes.get_attribute("n:a").namespace)
      assert_equal("urn:source", moved.attributes["xmlns:n"])
    end

    # The compensating declaration is added on the moved element, so
    # unrelated siblings in the target document keep their bindings.
    def test_added_declaration_does_not_affect_unrelated_siblings
      source = Document.new(%(<s xmlns:n="urn:source"><n:x/></s>))
      target = Document.new(%(<t xmlns:n="urn:target"><n:y/><n:z/></t>))

      MovePlan.new(source.root.elements[1], target.root).execute!

      assert_equal("urn:target", target.root.elements[1].namespace("n"))
      assert_equal("urn:target", target.root.elements[2].namespace("n"))
      assert_equal("urn:source", target.root.elements[3].namespace("n"))
      # The target root's own declaration is untouched.
      assert_equal("urn:target", target.root.attributes["xmlns:n"])
    end

    # When both documents bind the prefix to the same URI, no extra
    # declaration is needed.
    def test_same_prefix_same_uri_adds_no_declaration
      source = Document.new(%(<s xmlns:n="urn:shared"><n:x/></s>))
      target = Document.new(%(<t xmlns:n="urn:shared"/>))

      MovePlan.new(source.root.elements[1], target.root).execute!

      moved = target.root.elements[1]
      assert_equal("urn:shared", moved.namespace("n"))
      assert_nil(moved.attributes["xmlns:n"])
    end

    # A default namespace in the target must not leak into unprefixed
    # moved elements: an xmlns="" undeclaration is added instead.
    def test_default_namespace_does_not_leak_into_moved_subtree
      source = Document.new(%(<s><x>text</x></s>))
      target = Document.new(%(<t xmlns="urn:target"><y/></t>))

      MovePlan.new(source.root.elements[1], target.root).execute!

      moved = target.root.elements[2]
      assert_equal("", moved.namespace)
      assert_equal("", moved.attributes["xmlns"])
      assert_equal("urn:target", target.root.elements[1].namespace)
    end

    # Moving an ancestor into its own descendant is rejected, and both
    # documents are left unchanged.
    def test_ancestor_move_into_descendant_is_rejected
      document = Document.new(%(<a><b><c/></b></a>))
      a = document.root
      b = a.elements[1]
      c = b.elements[1]

      plan = MovePlan.new(b, c)
      assert_false(plan.valid?)
      assert_raise(MoveError) { plan.execute! }
      assert_equal("<a><b><c/></b></a>", document.to_s)
    end

    # Moving a node into itself is rejected as well.
    def test_move_into_self_is_rejected
      document = Document.new(%(<a><b/></a>))
      a = document.root

      plan = MovePlan.new(a, a)
      assert_false(plan.valid?)
      assert_raise(MoveError) { plan.execute! }
      assert_equal("<a><b/></a>", document.to_s)
    end

    # A prefix that is unbound in the source but bound in the target
    # cannot be preserved (XML 1.0 cannot undeclare a prefixed
    # namespace), so the move is rejected and nothing changes.
    def test_unbound_prefix_in_source_is_rejected
      # The tree parser rejects unbound prefixes, so build the source
      # tree programmatically.
      source = Document.new
      source.add_element("s").add_element("n:x")
      target = Document.new(%(<t xmlns:n="urn:target"/>))
      source_before = source.to_s
      target_before = target.to_s

      plan = MovePlan.new(source.root.elements[1], target.root)
      assert_false(plan.valid?)
      assert_raise(MoveError) { plan.execute! }
      assert_equal(source_before, source.to_s)
      assert_equal(target_before, target.to_s)
    end

    # A subtree whose attribute is owned by another element is rejected;
    # both documents stay untouched.
    def test_foreign_attribute_ownership_is_rejected
      source = Document.new(%(<s><x a="1"/></s>))
      target = Document.new(%(<t/>))
      node = source.root.elements[1]
      foreign = Element.new("foreign")
      node.attributes.get_attribute("a").element = foreign
      source_before = source.to_s
      target_before = target.to_s

      plan = MovePlan.new(node, target.root)
      assert_false(plan.valid?)
      assert_raise(MoveError) { plan.execute! }
      assert_equal(source_before, source.to_s)
      assert_equal(target_before, target.to_s)
    end

    # A subtree whose text node is not owned by its parent is rejected;
    # both documents stay untouched.
    def test_foreign_text_ownership_is_rejected
      source = Document.new(%(<s><x>text</x></s>))
      target = Document.new(%(<t/>))
      node = source.root.elements[1]
      text = node.children.first
      text.instance_variable_set(:@parent, Element.new("foreign"))
      source_before = source.to_s
      target_before = target.to_s

      plan = MovePlan.new(node, target.root)
      assert_false(plan.valid?)
      assert_raise(MoveError) { plan.execute! }
      assert_equal(source_before, source.to_s)
      assert_equal(target_before, target.to_s)
    end

    # The order of children (including text nodes) is preserved in both
    # the moved subtree and the target parent.
    def test_text_order_is_preserved
      source = Document.new(%(<s><x>t1<y/>t2</x></s>))
      target = Document.new(%(<t>head<z/>tail</t>))

      MovePlan.new(source.root.elements[1], target.root).execute!

      assert_equal("<t>head<z/>tail<x>t1<y/>t2</x></t>", target.to_s)
      assert_equal("<s/>", source.to_s)
    end

    # Child#move_to is a convenience wrapper around MovePlan.
    def test_move_to_convenience_method
      source = Document.new(%(<s xmlns:n="urn:source"><n:x/></s>))
      target = Document.new(%(<t xmlns:n="urn:target"/>))
      node = source.root.elements[1]

      assert_same(node, node.move_to(target.root))
      assert_equal("urn:source", target.root.elements[1].namespace("n"))
      assert_equal(0, source.root.elements.size)
    end

    # The original add_element interface is untouched and still works.
    def test_add_element_interface_is_unchanged
      element = Element.new("foo")
      child = element.add_element("bar", {"a" => "1"})
      assert_equal("bar", child.name)
      assert_equal("1", child.attributes["a"])
      other = element.add_element(Element.new("baz"))
      assert_equal("baz", other.name)
    end
  end
end
