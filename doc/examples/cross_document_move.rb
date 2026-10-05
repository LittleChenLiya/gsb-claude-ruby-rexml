# frozen_string_literal: false
#
# Two-document example for REXML::MovePlan: an explicit, validated
# cross-Document move that preserves node identity and namespace meaning.
#
# Run with:
#   ruby -Ilib doc/examples/cross_document_move.rb

require "rexml/document"

# Both documents bind the prefix "n" to *different* URIs.
source = REXML::Document.new(
  %(<s xmlns:n="urn:source"><n:item n:id="7">first</n:item><n:item/></s>))
target = REXML::Document.new(
  %(<t xmlns:n="urn:target"><n:entry>existing</n:entry></t>))

node = source.root.elements[1]

# Build an explicit plan and inspect it before touching either document.
plan = REXML::MovePlan.new(node, target.root)
puts "valid? #{plan.valid?}"          # => valid? true
puts "errors: #{plan.errors.inspect}" # => errors: []

plan.execute!

# The same node object was moved (identity preserved), and a local
# xmlns:n="urn:source" declaration was added on the moved element only,
# so the prefix still resolves to its original URI while the unrelated
# sibling <n:entry/> keeps resolving "n" to "urn:target".
moved = target.root.elements[2]
puts moved.equal?(node)                    # => true
puts moved.namespace("n")                  # => urn:source
puts target.root.elements[1].namespace("n") # => urn:target
puts target                                # => <t xmlns:n='urn:target'>...

# An ancestor cannot be moved into its own descendant: the plan is
# rejected and both documents are left unchanged.
cycle = REXML::MovePlan.new(target.root, moved)
puts "cycle valid? #{cycle.valid?}" # => cycle valid? false
begin
  cycle.execute!
rescue REXML::MoveError => error
  puts "rejected: #{error.message}"
end

