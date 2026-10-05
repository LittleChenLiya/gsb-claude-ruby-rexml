# frozen_string_literal: true

require_relative "element"

module REXML
  # ElementMove represents an explicit plan for moving an Element subtree to a
  # new parent, which may live in a different Document.
  #
  # Unlike simply reassigning +parent+, an ElementMove validates the whole
  # operation before touching either tree:
  #
  # * the moved element must not be moved into itself or one of its own
  #   descendants (that would create a cycle);
  # * every attribute and text node in the subtree must be owned by the
  #   subtree, so the move is well defined;
  # * every namespace prefix used by the subtree must keep its meaning.
  #
  # If a prefix used by the moved subtree is bound to a different URI at the
  # target, the plan adds a namespace declaration on the moved element so the
  # prefix keeps its source meaning.  The declaration only affects the moved
  # subtree; unrelated siblings in the target document are left untouched.
  #
  # If a prefix cannot be preserved (for example, it is unbound in the source
  # but bound in the target), the move is rejected and neither document is
  # modified.
  #
  #   doc_a = REXML::Document.new('<root xmlns:x="http://a"><x:foo/></root>')
  #   doc_b = REXML::Document.new('<root xmlns:x="http://b"><sibling/></root>')
  #   moved = doc_a.root.elements[1]
  #   target = doc_b.root.elements[1]
  #   REXML::ElementMove.new(moved, target).perform
  #   moved.namespace('x') # => "http://a"
  #
  class ElementMove
    # Raised when a move cannot be performed.  When this is raised, neither
    # the source nor the target document has been modified.
    class InvalidMove < StandardError; end

    attr_reader :element, :target

    def initialize(element, target)
      raise ArgumentError, "element must be an REXML::Element" unless element.is_a?(Element)
      raise ArgumentError, "cannot move a REXML::Document" if element.is_a?(Document)
      raise ArgumentError, "target must be an REXML::Element" unless target.is_a?(Element)

      @element = element
      @target = target
      @declarations = {}
    end

    # Validates the move.  Raises InvalidMove if the move cannot be performed.
    # This method does not modify either document.  Returns self.
    def validate
      @declarations = {}
      validate_not_ancestor
      validate_target
      validate_ownership
      validate_namespaces
      self
    end

    # Validates and executes the move atomically.  If validation fails,
    # InvalidMove is raised and neither document is modified.
    def perform
      validate
      apply_declarations
      perform_move
      element
    end

    private

    # Reject moving an element into itself or one of its own descendants; that
    # would create a cycle in the tree.
    def validate_not_ancestor
      node = target
      while node
        if node.equal?(element)
          raise InvalidMove,
                "cannot move #{element} to #{target}: " \
                "target is the element itself or a descendant of it"
        end
        node = node.parent
      end
    end

    # A Document can only hold one root element; reject if the target document
    # already has a different root.
    def validate_target
      if target.is_a?(Document) && target.root && !target.root.equal?(element)
        raise InvalidMove,
              "target document already has a root element: #{target.root}"
      end
    end

    # Verify that every attribute and child node in the subtree is owned by
    # the subtree, so the move is well defined.
    def validate_ownership
      each_subtree_element do |el|
        el.attributes.each_attribute do |attr|
          unless attr.element.equal?(el)
            raise InvalidMove,
                  "attribute #{attr.expanded_name} is not owned by #{el}"
          end
        end
        el.children.each do |child|
          unless child.parent.equal?(el)
            raise InvalidMove,
                  "child #{child.inspect} is not owned by #{el}"
          end
        end
      end
    end

    # Collect the prefixes used by the subtree that are not declared within
    # the subtree itself, and compare their source binding with the binding at
    # the target.  When they differ, plan a declaration on the moved element so
    # the prefix keeps its source meaning.
    def validate_namespaces
      used_prefixes = {}
      each_subtree_element do |el|
        collect_prefix(used_prefixes, el, el.prefix)
        el.attributes.each_attribute do |attr|
          next if attr.prefix.nil? || attr.prefix == ""
          next if attr.prefix == "xmlns" # namespace declarations move with the subtree
          collect_prefix(used_prefixes, el, attr.prefix)
        end
      end

      used_prefixes.each do |prefix, _|
        next if self_declares?(element, prefix)

        source_uri = lookup_namespace(element, prefix)
        target_uri = lookup_namespace(target, prefix)
        next if source_uri == target_uri

        if source_uri.nil?
          raise InvalidMove,
                "prefix #{prefix.inspect} is unbound in the source but bound " \
                "to #{target_uri.inspect} at the target; its meaning cannot " \
                "be preserved"
        end
        @declarations[prefix] = source_uri
      end
    end

    def collect_prefix(used, el, prefix)
      return if prefix.nil?
      return if prefix == "xmlns"
      used[prefix] = true
    end

    # Whether +el+ itself declares the given prefix (so the declaration moves
    # with the subtree and no external binding is involved).
    def self_declares?(el, prefix)
      if prefix == ""
        !el.attributes.get_attribute("xmlns").nil?
      else
        !el.attributes.get_attribute("xmlns:#{prefix}").nil?
      end
    end

    def lookup_namespace(node, prefix)
      if prefix == ""
        node.namespace("")
      else
        node.namespace(prefix)
      end
    end

    def apply_declarations
      @declarations.each do |prefix, uri|
        if prefix == ""
          element.add_namespace(uri)
        else
          element.add_namespace(prefix, uri)
        end
      end
    end

    def perform_move
      old_parent = element.parent
      return if old_parent.equal?(target)

      old_parent.delete(element) if old_parent
      target.add(element)
    end

    def each_subtree_element(&block)
      yield element
      element.each_recursive do |node|
        yield node if node.is_a?(Element)
      end
    end
  end
end
