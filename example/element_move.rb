# frozen_string_literal: true

# Two-document example for REXML::ElementMove / Element#move_to.
#
# Demonstrates moving an element from one document to another when both
# documents bind the same prefix to different namespace URIs.  The moved
# element keeps its source namespace meaning: a namespace declaration is added
# on the moved element itself, so unrelated siblings in the target document
# are unaffected.
#
# Run with:
#   ruby -Ilib example/element_move.rb

require "rexml/document"
require "rexml/element_move"

doc_a = REXML::Document.new(<<~XML)
  <root xmlns:x="http://a">
    <x:foo x:id="1">hello<x:b/>world</x:foo>
  </root>
XML

doc_b = REXML::Document.new(<<~XML)
  <root xmlns:x="http://b">
    <sibling>sib</sibling>
    <other/>
  </root>
XML

moved = doc_a.root.elements[1]
target = doc_b.root.elements[1]

puts "Before:"
puts "  doc_a: #{doc_a}"
puts "  doc_b: #{doc_b}"
puts "  moved namespace: #{moved.namespace('x')}"
puts "  target namespace: #{target.namespace('x')}"

moved.move_to(target)

puts
puts "After moving <x:foo> from doc_a into doc_b's <sibling>:"
puts "  doc_a: #{doc_a}"
puts "  doc_b: #{doc_b}"
puts "  moved namespace: #{moved.namespace('x')} (still http://a)"
puts "  sibling namespace: #{target.namespace('x')} (still http://b)"
puts "  sibling has declaration? #{target.attributes.get_attribute('xmlns:x') != nil}"
puts "  moved has declaration? #{moved.attributes.get_attribute('xmlns:x') != nil}"
puts "  text order: #{moved.texts.map(&:to_s).inspect}"
