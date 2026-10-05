# frozen_string_literal: false
require_relative "element"

module REXML
  # Raised when a planned node move cannot be performed.  Both the source
  # and the target documents are left unchanged when this is raised.
  class MoveError < RuntimeError
  end

  # An explicit plan for moving a node (typically an Element) from its
  # current parent to another parent, possibly in a different Document.
  #
  # The move is *not* a copy: the node object itself is relocated, so its
  # identity (object_id) and the order of its children (elements, texts,
  # ...) are preserved.  Only the parent linkage changes.
  #
  # Everything is validated before anything is mutated:
  #
  # * Cycle check: a node cannot be moved into itself or into one of its
  #   own descendants.
  # * Ownership check: every descendant child (elements, text nodes, ...)
  #   must actually belong to its parent in the moved subtree, and every
  #   attribute must belong to its element.
  # * Namespace check: every namespace prefix used by the moved subtree
  #   must resolve to the same URI after the move.  When the target
  #   context binds a used prefix to a different URI, the plan adds a
  #   local namespace declaration on the moved element itself (never on
  #   the target parent, so unrelated siblings keep their meaning).  If
  #   such a declaration cannot be added (reserved prefix, or a prefix
  #   that is unbound in the source but bound in the target), the plan
  #   is invalid and the move is rejected.
  #
  # If any check fails, #execute! raises MoveError and both the source
  # and the target documents are left untouched.
  #
  #   source = REXML::Document.new(%(<s xmlns:n="urn:a"><n:x>hi</n:x></s>))
  #   target = REXML::Document.new(%(<t xmlns:n="urn:b"><n:y/></t>))
  #   node = source.root.elements[1]
  #   plan = REXML::MovePlan.new(node, target.root)
  #   plan.valid?   # => true (a xmlns:n="urn:a" declaration will be
  #                 #           added on the moved element itself)
  #   plan.execute!
  #   target.root.elements[2].namespace("n")  # => "urn:a"
  #   target.root.elements[1].namespace("n")  # => "urn:b" (unchanged)
  class MovePlan
    # The node to be moved.
    attr_reader :node
    # The parent (Element or Document) the node will be moved into.
    attr_reader :new_parent
    # The list of validation error messages.  Empty when the plan is valid.
    attr_reader :errors

    # The namespace URI the reserved "xml" prefix is always bound to.
    XML_PREFIX_URI = "http://www.w3.org/XML/1998/namespace"

    def initialize(node, new_parent)
      @node = node
      @new_parent = new_parent
      @errors = []
      # Namespace declarations ([attribute_name, uri] pairs) to add on
      # the moved element so that its subtree keeps its namespace meaning.
      @declarations = []
      @validated = false
    end

    # Returns true if the move can be performed, false otherwise.
    # Validation is performed at most once; see #errors for details.
    def valid?
      validate unless @validated
      @errors.empty?
    end

    # Performs the move.  Raises MoveError if the plan is invalid; in
    # that case neither the source nor the target document is modified.
    # Returns the moved node.
    def execute!
      unless valid?
        raise MoveError,
              "cannot move #{@node.inspect}: #{@errors.join('; ')}"
      end
      @node.parent.delete(@node) if @node.parent
      @declarations.each do |attribute_name, uri|
        @node.attributes[attribute_name] = uri
      end
      @new_parent.add(@node)
      @node
    end

    private

    def validate
      @validated = true
      return unless check_types
      check_cycle
      check_ownership
      plan_namespaces
    end

    def check_types
      if @node.is_a?(Document) or not @node.is_a?(Child)
        @errors << "moved node must be a child node (not a Document)"
        return false
      end
      unless @new_parent.is_a?(Parent)
        @errors << "move target must be an Element or a Document"
        return false
      end
      true
    end

    def check_cycle
      ancestor = @new_parent
      while ancestor
        if ancestor.equal?(@node)
          @errors << "cannot move a node into itself or its own descendant"
          return
        end
        ancestor = ancestor.parent
      end
    end

    # Verifies that every descendant child belongs to its parent and that
    # every attribute belongs to its element, so that relocating the
    # subtree cannot smuggle in nodes owned by another tree.
    def check_ownership
      return unless @node.is_a?(Parent)
      walk = nil
      walk = lambda do |parent|
        parent.each_child do |child|
          unless child.parent.equal?(parent)
            @errors << "child #{child.inspect} is not owned by #{parent.inspect}"
          end
          walk.call(child) if child.is_a?(Parent)
        end
        if parent.is_a?(Element)
          parent.attributes.each_value do |attribute|
            unless attribute.element.equal?(parent)
              @errors << "attribute #{attribute.name.inspect} is not owned " \
                         "by #{parent.inspect}"
            end
          end
        end
      end
      walk.call(@node)
    end

    # Computes the namespace declarations that must be added on the moved
    # element so that every prefix used in its subtree resolves to the
    # same URI in the target context as it did in the source context.
    def plan_namespaces
      return unless @node.is_a?(Element)
      source_bindings = @node.parent ? @node.parent.namespaces : {}
      target_bindings = @new_parent.namespaces
      used_prefixes.each do |key|
        source_uri = effective_binding(source_bindings, key)
        target_uri = effective_binding(target_bindings, key)
        next if source_uri == target_uri
        if key == "xml"
          @errors << "cannot preserve binding of reserved prefix 'xml'"
        elsif key == "xmlns"
          # The default namespace can always be re-declared (or
          # undeclared with an empty URI) on the moved element.
          @declarations << ["xmlns", source_uri || ""]
        elsif source_uri.nil?
          # XML 1.0 cannot undeclare a prefixed namespace, so an unbound
          # prefix cannot be preserved where the target binds it.
          @errors << "prefix #{key.inspect} is unbound in the source but " \
                     "bound in the target; cannot preserve its meaning"
        else
          @declarations << ["xmlns:#{key}", source_uri]
        end
      end
    end

    def effective_binding(bindings, key)
      uri = bindings[key]
      uri = XML_PREFIX_URI if key == "xml" and uri.nil?
      uri
    end

    # Returns the namespace keys ("xmlns" for the default namespace,
    # otherwise the prefix) that are used by the moved subtree and
    # resolved by declarations at or above the moved node.  Prefixes
    # declared inside the subtree travel with it and need no planning.
    def used_prefixes
      used = []
      walk = nil
      walk = lambda do |element, inherited|
        local = []
        element.attributes.each_value do |attribute|
          local << attribute.name if attribute.namespace_declaration?
        end
        visible = inherited | local
        prefix = element.prefix
        key = (prefix.nil? or prefix.empty?) ? "xmlns" : prefix
        used << key unless visible.include?(key)
        element.attributes.each_value do |attribute|
          next if attribute.namespace_declaration?
          prefix = attribute.prefix
          next if prefix.nil? or prefix.empty?
          used << prefix unless visible.include?(prefix)
        end
        element.elements.each do |child|
          walk.call(child, visible)
        end
      end
      walk.call(@node, [])
      used.uniq
    end
  end

  class Child
    # Moves this node into +new_parent+ (an Element or a Document,
    # possibly in a different Document) using an explicit MovePlan.
    # Raises MoveError and leaves both documents unchanged if the move
    # cannot be performed safely.  Returns the moved node.
    def move_to(new_parent)
      MovePlan.new(self, new_parent).execute!
    end
  end
end
