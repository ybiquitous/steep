require "test_helper"

class TypeConstructionTest < Minitest::Test
  Source = Steep::Source
  TypeAssignability = Steep::TypeAssignability
  Typing = Steep::Typing
  TypeConstruction = Steep::TypeConstruction
  Parser = Steep::Parser
  Annotation = Steep::Annotation
  Types = Steep::Types

  include TestHelper
  include TypeErrorAssertions

  def ruby(string)
    Steep::Source.parse(string, path: Pathname("foo.rb"))
  end

  def assignability
    TypeAssignability.new.tap do |assignability|
      interfaces = Parser.parse_interfaces(<<-EOS)
interface A
  def +: (A) -> A
end

interface B
end

interface C
  def f: () -> A
  def g: (A, ?B) -> B
  def h: (a: A, ?b: B) -> C
end

interface X
  def f: () { (A) -> B } -> C 
end
      EOS
      interfaces.each do |interface|
        assignability.add_interface interface
      end
    end
  end

  def test_lvar_with_annotation
    source = ruby(<<-EOF)
# @type var x: A
x = nil
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :A, params: []), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_lvar_with_annotation_type_check
    source = ruby(<<-EOF)
# @type var x: B
# @type var z: A
x = nil
z = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :A, params: []), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_incompatible_assignment typing.errors[0],
                                   lhs_type: Types::Name.new(name: :A, params: []),
                                   rhs_type: Types::Name.new(name: :B, params: []) do |error|
      assert_equal :lvasgn, error.node.type
      assert_equal :z, error.node.children[0].name
    end
  end

  def test_lvar_without_annotation
    source = ruby(<<-EOF)
x = 1
z = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_lvar_without_annotation_inference
    source = ruby(<<-EOF)
# @type var x: A
x = nil
z = x
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :A, params: []), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call
    source = ruby(<<-EOF)
# @type var x: C
x = nil
x.f
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :A, params: []), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_with_argument
    source = ruby(<<-EOF)
# @type var x: C
# @type var y: A
x = nil
y = nil
x.g(y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :B, params: []), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_incompatible_argument_type
    source = ruby(<<-EOF)
# @type var x: C
# @type var y: B
x = nil
y = nil
x.g(y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :B, params: []), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_invalid_argument_error typing.errors[0],
                                  expected_type: Types::Name.new(name: :A, params: []),
                                  actual_type: Types::Name.new(name: :B, params: [])
  end

  def test_method_call_no_error_if_any
    source = ruby(<<-EOF)
x = nil
x.no_such_method
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_method_call_no_method_error
    source = ruby(<<-EOF)
# @type var x: C
x = nil
x.no_such_method
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Any.new, typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_no_method_error typing.errors.first, method: :no_such_method, type: Types::Name.new(name: :C, params: [])
  end

  def test_method_call_missing_argument
    source = ruby(<<-EOF)
# @type var x: A
# @type var a: C
a = nil
x = nil
a.g()
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :B, params: []), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_expected_argument_missing typing.errors.first, index: 0
  end

  def test_method_call_extra_args
    source = ruby(<<-EOF)
# @type var x: A
# @type var a: C
a = nil
x = nil
a.g(nil, nil, nil)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :B, params: []), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_extra_argument_given typing.errors.first, index: 2
  end

  def test_keyword_call
    source = ruby(<<-EOF)
# @type var x: C
# @type var a: A
# @type var b: B
x = nil
a = nil
b = nil
x.h(a: a, b: b)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :C, params: []), typing.type_of(node: source.node)
    assert_empty typing.errors
  end

  def test_keyword_missing
    source = ruby(<<-EOF)
# @type var x: C
x = nil
x.h()
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :C, params: []), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_expected_keyword_missing typing.errors[0], keyword: :a
  end

  def test_extra_keyword_given
    source = ruby(<<-EOF)
# @type var x: C
x = nil
x.h(a: nil, b: nil, c: nil)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :C, params: []), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_extra_keyword_given typing.errors[0], keyword: :c
  end

  def test_keyword_typecheck
    source = ruby(<<-EOF)
# @type var x: C
# @type var y: B
x = nil
y = nil
x.h(a: y)
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :C, params: []), typing.type_of(node: source.node)

    assert_equal 1, typing.errors.size
    assert_invalid_argument_error typing.errors[0], expected_type: Types::Name.new(name: :A, params: []), actual_type: Types::Name.new(name: :B, params: [])
  end

  def test_def_no_params
    source = ruby(<<-EOF)
def foo
  # @type var x: A
  x = nil
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    def_body = source.node.children[2]
    assert_equal Types::Name.new(name: :A, params: []), typing.type_of(node: def_body)
  end

  def test_def_param
    source = ruby(<<-EOF)
def foo(x)
  # @type var x: A
  y = x
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    def_body = source.node.children[2]
    assert_equal Types::Name.new(name: :A, params: []), typing.type_of(node: def_body)
    assert_equal Types::Name.new(name: :A, params: []), typing.type_of_variable(name: :x)
    assert_equal Types::Name.new(name: :A, params: []), typing.type_of_variable(name: :y)
  end

  def test_def_param_error
    source = ruby(<<-EOF)
def foo(x, y = x)
  # @type var x: A
  # @type var y: C
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    refute_empty typing.errors
    assert_incompatible_assignment typing.errors[0],
                                   lhs_type: Types::Name.new(name: :C, params: []),
                                   rhs_type: Types::Name.new(name: :A, params: []) do |error|
      assert_equal :optarg, error.node.type
      assert_equal :y, error.node.children[0].name
    end

    assert_equal Types::Name.new(name: :A, params: []), typing.type_of_variable(name: :x)
    assert_equal Types::Name.new(name: :C, params: []), typing.type_of_variable(name: :y)
  end

  def test_def_kw_param_error
    source = ruby(<<-EOF)
def foo(x:, y: x)
  # @type var x: A
  # @type var y: C
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    refute_empty typing.errors
    assert_incompatible_assignment typing.errors[0],
                                   lhs_type: Types::Name.new(name: :C, params: []),
                                   rhs_type: Types::Name.new(name: :A, params: []) do |error|
      assert_equal :kwoptarg, error.node.type
      assert_equal :y, error.node.children[0].name
    end

    assert_equal Types::Name.new(name: :A, params: []), typing.type_of_variable(name: :x)
    assert_equal Types::Name.new(name: :C, params: []), typing.type_of_variable(name: :y)
  end

  def test_block
    source = ruby(<<-EOF)
# @type var a: X
a = nil

b = a.f do |x|
  # @type var x: A
  # @type var y: B
  y = nil
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_equal Types::Name.new(name: :X, params: []), typing.type_of_variable(name: :a)
    assert_equal Types::Name.new(name: :C, params: []), typing.type_of_variable(name: :b)
    assert_equal Types::Name.new(name: :A, params: []), typing.type_of_variable(name: :x)
    assert_equal Types::Name.new(name: :B, params: []), typing.type_of_variable(name: :y)
  end

  def test_block_shadow
    source = ruby(<<-EOF)
# @type var a: X
a = nil

a.f do |a|
  # @type var a: A
  b = a
end
    EOF

    typing = Typing.new
    annotations = source.annotations(block: source.node)

    construction = TypeConstruction.new(assignability: assignability, source: source, annotations: annotations, var_types: {}, typing: typing)
    construction.run(source.node)

    assert_any typing.var_typing do |var, type| var.name == :a && type.is_a?(Types::Name) && type.name == :A end
    assert_any typing.var_typing do |var, type| var.name == :a && type.is_a?(Types::Name) && type.name == :X end
    assert_equal Types::Name.new(name: :A, params: []), typing.type_of_variable(name: :b)
  end

  def arguments(ruby)
    ::Parser::CurrentRuby.parse(ruby).children.drop(2)
  end

  def test_argument_pairs
    params = Types::Interface::Params.empty.with(required: [Types::Name.new(name: :A, params: [])],
                                                 optional: [Types::Name.new(name: :B, params: [])],
                                                 rest: Types::Name.new(name: :C, params: []),
                                                 required_keywords: { d: Types::Name.new(name: :D, params: []) },
                                                 optional_keywords: { e: Types::Name.new(name: :E, params: []) },
                                                 rest_keywords: Types::Name.new(name: :F, params: []))
    arguments = arguments("f(a, b, c, d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.new(name: :A, params: []), arguments[0]],
                   [Types::Name.new(name: :B, params: []), arguments[1]],
                   [Types::Name.new(name: :C, params: []), arguments[2]],
                   [Types::Name.new(name: :D, params: []), arguments[3].children[0].children[1]],
                   [Types::Name.new(name: :E, params: []), arguments[3].children[1].children[1]],
                   [Types::Name.new(name: :F, params: []), arguments[3].children[2].children[1]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_pairs_rest_keywords
    params = Types::Interface::Params.empty.with(required: [Types::Name.new(name: :A, params: [])],
                                                 optional: [Types::Name.new(name: :B, params: [])],
                                                 rest: Types::Name.new(name: :C, params: []),
                                                 required_keywords: { d: Types::Name.new(name: :D, params: []) },
                                                 optional_keywords: { e: Types::Name.new(name: :E, params: []) },
                                                 rest_keywords: Types::Name.new(name: :F, params: []))
    arguments = arguments("f(a, b, c, d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.new(name: :A, params: []), arguments[0]],
                   [Types::Name.new(name: :B, params: []), arguments[1]],
                   [Types::Name.new(name: :C, params: []), arguments[2]],
                   [Types::Name.new(name: :D, params: []), arguments[3].children[0].children[1]],
                   [Types::Name.new(name: :E, params: []), arguments[3].children[1].children[1]],
                   [Types::Name.new(name: :F, params: []), arguments[3].children[2].children[1]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_pairs_required
    params = Types::Interface::Params.empty.with(required: [Types::Name.new(name: :A, params: [])],
                                                 optional: [Types::Name.new(name: :B, params: [])],
                                                 rest: Types::Name.new(name: :C, params: []))
    arguments = arguments("f(a, b, c)")

    assert_equal [
                   [Types::Name.new(name: :A, params: []), arguments[0]],
                   [Types::Name.new(name: :B, params: []), arguments[1]],
                   [Types::Name.new(name: :C, params: []), arguments[2]],
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_pairs_hash
    params = Types::Interface::Params.empty.with(required: [Types::Name.new(name: :A, params: [])],
                                                 optional: [Types::Name.new(name: :B, params: [])],
                                                 rest: Types::Name.new(name: :C, params: []))
    arguments = arguments("f(a, b, c, d: d)")

    assert_equal [
                   [Types::Name.new(name: :A, params: []), arguments[0]],
                   [Types::Name.new(name: :B, params: []), arguments[1]],
                   [Types::Name.new(name: :C, params: []), arguments[2]],
                   [Types::Name.new(name: :C, params: []), arguments[3]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_keywords
    params = Types::Interface::Params.empty.with(required_keywords: { d: Types::Name.new(name: :D, params: []) },
                                                 optional_keywords: { e: Types::Name.new(name: :E, params: []) },
                                                 rest_keywords: Types::Name.new(name: :F, params: []))

    arguments = arguments("f(d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.new(name: :D, params: []), arguments[0].children[0].children[1]],
                   [Types::Name.new(name: :E, params: []), arguments[0].children[1].children[1]],
                   [Types::Name.new(name: :F, params: []), arguments[0].children[2].children[1]],
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end

  def test_argument_hash_not_keywords
    params = Types::Interface::Params.empty.with(required: [Types::Name.new(name: :A, params: [])])

    arguments = arguments("f(d: d, e: e, f: f)")

    assert_equal [
                   [Types::Name.new(name: :A, params: []), arguments[0]]
                 ], TypeConstruction.argument_typing_pairs(params: params, arguments: arguments)
  end
end
