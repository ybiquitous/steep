require_relative "test_helper"

# (Almost) end-to-end type checking test
#
# Specify the type definition, Ruby code, and expected diagnostics.
# Running test here allows using debuggers.
#
# You can use `Add type_check_test case` VSCode snippet to add new test case.
#
class TypeCheckTest < Minitest::Test
  include TestHelper
  include TypeErrorAssertions
  include FactoryHelper
  include SubtypingHelper
  include TypeConstructionHelper

  include Steep

  def run_type_check_test(signatures: {}, code: {}, expectations: nil)
    typings = {}

    with_factory(signatures, nostdlib: false) do |factory|
      builder = Interface::Builder.new(factory)
      subtyping = Subtyping::Check.new(builder: builder)

      code.each do |path, content|
        source = Source.parse(content, path: path, factory: factory)
        with_standard_construction(subtyping, source) do |construction, typing|
          construction.synthesize(source.node)

          typings[path] = typing
        end
      end
    end

    yield typings if block_given?

    formatter = Diagnostic::LSPFormatter.new()

    diagnostics = typings.transform_values do |typing|
      typing.errors.map do |error|
        Expectations::Diagnostic.from_lsp(formatter.format(error))
      end
    end

    if expectations
      exps = Expectations.empty
      diagnostics.each do |path, ds|
        exps.diagnostics[path] = ds
      end
      exps.to_yaml

      assert_equal expectations, exps.to_yaml
    end
  end

  def test_setter_type
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class SetterReturnType
            def foo=: (String) -> String
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class SetterReturnType
            def foo=(value)
              if _ = value
                return
              else
                123
              end
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 6
              end:
                line: 2
                character: 10
            severity: ERROR
            message: |-
              Setter method `foo=` cannot have type `::Integer` because declared as type `::String`
                ::Integer <: ::String
                  ::Numeric <: ::String
                    ::Object <: ::String
                      ::BasicObject <: ::String
            code: Ruby::SetterBodyTypeMismatch
          - range:
              start:
                line: 4
                character: 6
              end:
                line: 4
                character: 12
            severity: ERROR
            message: |-
              The setter method `foo=` cannot return a value of type `nil` because declared as type `::String`
                nil <: ::String
            code: Ruby::SetterReturnTypeMismatch
      YAML
    )
  end

  def test_lambda_method
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          # @type var f: ^(Integer) -> Integer
          f = lambda {|x| x + 1 }

          g = lambda {|x| x + 1 } #: ^(Integer) -> String
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 11
              end:
                line: 4
                character: 23
            severity: ERROR
            message: |-
              Cannot allow block body have type `::Integer` because declared as type `::String`
                ::Integer <: ::String
                  ::Numeric <: ::String
                    ::Object <: ::String
                      ::BasicObject <: ::String
            code: Ruby::BlockBodyTypeMismatch
      YAML
    )
  end

  def test_back_ref
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          # @type var x: String
          x = $&
          x = $'
          x = $+
          x = $,
          x = $'
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 0
              end:
                line: 2
                character: 6
            severity: ERROR
            message: |-
              Cannot assign a value of type `(::String | nil)` to a variable of type `::String`
                (::String | nil) <: ::String
                  nil <: ::String
            code: Ruby::IncompatibleAssignment
          - range:
              start:
                line: 3
                character: 0
              end:
                line: 3
                character: 6
            severity: ERROR
            message: |-
              Cannot assign a value of type `(::String | nil)` to a variable of type `::String`
                (::String | nil) <: ::String
                  nil <: ::String
            code: Ruby::IncompatibleAssignment
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 6
            severity: ERROR
            message: |-
              Cannot assign a value of type `(::String | nil)` to a variable of type `::String`
                (::String | nil) <: ::String
                  nil <: ::String
            code: Ruby::IncompatibleAssignment
          - range:
              start:
                line: 5
                character: 0
              end:
                line: 5
                character: 6
            severity: ERROR
            message: |-
              Cannot assign a value of type `(::String | nil)` to a variable of type `::String`
                (::String | nil) <: ::String
                  nil <: ::String
            code: Ruby::IncompatibleAssignment
          - range:
              start:
                line: 6
                character: 0
              end:
                line: 6
                character: 6
            severity: ERROR
            message: |-
              Cannot assign a value of type `(::String | nil)` to a variable of type `::String`
                (::String | nil) <: ::String
                  nil <: ::String
            code: Ruby::IncompatibleAssignment
      YAML
    )
  end

  def test_type_variable_in_Set_new
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          # @type var array: _Each[Integer]
          array = [1,2,3]

          a = Set.new([1, 2, 3])
          a.each do |x|
            x.fooo
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 6
                character: 4
              end:
                line: 6
                character: 8
            severity: ERROR
            message: Type `::Integer` does not have method `fooo`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_if_unreachable
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          x = 123 #: Integer

          if x.is_a?(String)
            foo()
          end

          if x.is_a?(Integer)
          else
            bar()
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 3
                character: 0
              end:
                line: 3
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 4
                character: 2
              end:
                line: 4
                character: 5
            severity: ERROR
            message: Type `::Object` does not have method `foo`
            code: Ruby::NoMethod
          - range:
              start:
                line: 8
                character: 0
              end:
                line: 8
                character: 4
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 9
                character: 2
              end:
                line: 9
                character: 5
            severity: ERROR
            message: Type `::Object` does not have method `bar`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_if_unreachable__if_then
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          # Then branch is unreachable
          if nil then
            123
          else
            123
          end

          if nil
            123
          else
            123
          end

          if nil
            123
          end

          123 if nil
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 7
              end:
                line: 2
                character: 11
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 8
                character: 0
              end:
                line: 8
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 14
                character: 0
              end:
                line: 14
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 18
                character: 4
              end:
                line: 18
                character: 6
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end

  def test_if_unreachable__if_else
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          # Else branch is unreachable
          if 123 then
            123
          else
            123
          end

          if 123
            123
          else
            123
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 4
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 10
                character: 0
              end:
                line: 10
                character: 4
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end

  def test_if_unreachable__unless_then
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          # Then branch is unreachable
          unless true then
            123
          else
            123
          end

          unless true
            123
          else
            123
          end

          unless true
            123
          end

          123 unless true
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 12
              end:
                line: 2
                character: 16
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 8
                character: 0
              end:
                line: 8
                character: 6
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 14
                character: 0
              end:
                line: 14
                character: 6
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 18
                character: 4
              end:
                line: 18
                character: 10
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end


  def test_if_unreachable__unless_else
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          # Else branch is unreachable
          unless false then
            123
          else
            123
          end

          unless false
            123
          else
            123
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 4
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 10
                character: 0
              end:
                line: 10
                character: 4
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end

  def test_case_unreachable_1
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          x = 123

          case x
          when String
            x.is_a_string
          when Integer
            x + 1
          when Array
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `untyped` but unreachable
            code: Ruby::UnreachableValueBranch
          - range:
              start:
                line: 5
                character: 4
              end:
                line: 5
                character: 15
            severity: ERROR
            message: Type `::String` does not have method `is_a_string`
            code: Ruby::NoMethod
          - range:
              start:
                line: 8
                character: 0
              end:
                line: 8
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `nil` but unreachable
            code: Ruby::UnreachableValueBranch
      YAML
    )
  end

  def test_case_unreachable_2
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          x = 123
          case
          when x.is_a?(String)
            x.is_a_string
          when x.is_a?(Integer)
            x+1
          when x.is_a?(Array)
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 3
                character: 0
              end:
                line: 3
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `untyped` but unreachable
            code: Ruby::UnreachableValueBranch
          - range:
              start:
                line: 4
                character: 4
              end:
                line: 4
                character: 15
            severity: ERROR
            message: Type `::String` does not have method `is_a_string`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_case_unreachable_3
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          case x = 123
          when Integer
            x+1
          else
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `nil` but unreachable
            code: Ruby::UnreachableValueBranch
      YAML
    )
  end

  def test_flow_sensitive__csend
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          x = nil #: Integer?

          if x&.nonzero?
            x.no_method_in_then
          else
            x.no_method_in_else
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 4
              end:
                line: 4
                character: 21
            severity: ERROR
            message: Type `::Integer` does not have method `no_method_in_then`
            code: Ruby::NoMethod
          - range:
              start:
                line: 6
                character: 4
              end:
                line: 6
                character: 21
            severity: ERROR
            message: Type `(::Integer | nil)` does not have method `no_method_in_else`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_flow_sensitive__csend2
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          x = nil #: Integer?

          if x&.is_a?(String)
            x.no_method_in_then
          else
            x.no_method_in_else
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 3
                character: 0
              end:
                line: 3
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 4
                character: 4
              end:
                line: 4
                character: 21
            severity: ERROR
            message: Type `::String` does not have method `no_method_in_then`
            code: Ruby::NoMethod
          - range:
              start:
                line: 6
                character: 4
              end:
                line: 6
                character: 21
            severity: ERROR
            message: Type `(::Integer | nil)` does not have method `no_method_in_else`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_flow_sensitive__self
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            attr_reader name: String?
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Hello.new.instance_eval do
            if self.name
              self.name + "!"
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_flow_sensitive__self2
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            attr_reader name: String?

            def foo: { () [self: self] -> void } -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Hello.new.foo do
            if self.name
              Hello.new.foo do
                self.name + "!"
              end
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 16
              end:
                line: 4
                character: 17
            severity: ERROR
            message: Type `(::String | nil)` does not have method `+`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_flow_sensitive__self3
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            attr_reader name: String?

            def foo: { () -> void } -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Hello.new.foo do
            # @type self: Hello
            if self.name
              Hello.new.foo do
                # @type self: Hello
                self.name + "!"
              end
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 6
                character: 16
              end:
                line: 6
                character: 17
            severity: ERROR
            message: Type `(::String | nil)` does not have method `+`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_flow_sensitive__self4
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            attr_reader name: String?

            def foo: { () -> void } -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Hello.new.foo do
            # @type self: Hello
            if self.name
              Hello.new.foo do
                self.name + "!"
              end
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_and_shortcut__truthy
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          x = [1].first
          1 and return unless x
          x + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_and_shortcut__false
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          x = [1].first
          return and true unless x
          x + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_or_shortcut__nil
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          x = [1].first
          nil or return unless x
          x + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_or_shortcut__false
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          x = [1].first
          x or return unless x
          x + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_type_assertion__generic_type_error
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            class Bar
            end
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Foo
            a = [] #: Array[Bar]
            a.map {|x| x } #$ Bar
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_type_case__local_variable_narrowing
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          type foo = Integer | String | nil
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          foo = 3 #: foo

          case foo
          when Integer
            1
          when String, nil
            2
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    ) do |typings|
      typing = typings["a.rb"]
      node, * = typing.source.find_nodes(line: 3, column: 6)

      assert_equal "::foo", typing.type_of(node: node).to_s
    end
  end

  def test_branch_unreachable__logic_type
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          x = 1
          y = x.is_a?(String)

          if y
            z = 1
          else
            z = 2
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_type_case__returns_nil_untyped_union
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          x = _ = 1
          y = _ = 2
          z = _ = 3

          a =
            case x
            when :foo
              y
            when :bar
              z
            end

          a.is_untyped
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 13
                character: 2
              end:
                line: 13
                character: 12
            severity: ERROR
            message: Type `nil` does not have method `is_untyped`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_case_when__no_subject__reachability
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          case
          when false
            :a
          when nil
            :b
          when "".is_a?(NilClass)
            :c
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 0
              end:
                line: 2
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `::Symbol` but unreachable
            code: Ruby::UnreachableValueBranch
          - range:
              start:
                line: 4
                character: 0
              end:
                line: 4
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `::Symbol` but unreachable
            code: Ruby::UnreachableValueBranch
          - range:
              start:
                line: 6
                character: 0
              end:
                line: 6
                character: 4
            severity: ERROR
            message: The branch may evaluate to a value of `::Symbol` but unreachable
            code: Ruby::UnreachableValueBranch
      YAML
    )
  end

  def test_case_when__no_subject__reachability_no_continue
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          case
          when true
            :a
          when 1
            :b
          else
            :c
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_case_when__untyped_value
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          foo = true #: untyped

          case foo
          when nil
            1
          when true
            2
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_case_when__narrow_pure_call
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class CaseWhenNarrowPure
            attr_reader foo: Integer | String | Array[String]
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          test = CaseWhenNarrowPure.new

          case test.foo
          when Integer
            test.foo + 1
          when String
            test.foo + ""
          else
            test.foo.each
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_case_when__bool_value
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          foo = true #: bool

          case foo
          when false
            1
          when true
            2
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_type_inference__nested_block
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          a = 123.yield_self do
            "abc".yield_self do
              :hogehoge
            end
          end

          a.is_symbol
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 7
                character: 2
              end:
                line: 7
                character: 11
            severity: ERROR
            message: Type `::Symbol` does not have method `is_symbol`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_type_inference__nested_block_free_variable
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo[T]
            def foo: () -> T
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          # Type error is reported because `::Symbol`` cannot be `T`
          class Foo
            def foo
              "".yield_self do
                :symbol
              end
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 4
                character: 18
              end:
                line: 6
                character: 7
            severity: ERROR
            message: |-
              Cannot allow block body have type `::Symbol` because declared as type `T`
                ::Symbol <: T
            code: Ruby::BlockBodyTypeMismatch
        YAML
    )
  end

  def test_type_narrowing__local_variable_safe_navigation_operator
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            type context = [context, String | false] | nil
            def foo: (context) -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Hello
            def foo(context)
              context&.[](0)
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_argument_error__unexpected_unexpected_positional_argument
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def foo: () -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          Foo.new.foo(hello_world: true)
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 12
              end:
                line: 1
                character: 23
            severity: ERROR
            message: Unexpected keyword argument
            code: Ruby::UnexpectedKeywordArgument
      YAML
    )
  end

  def test_type_assertion__type_error
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          nil #: Int
          [1].map {} #$ Int
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 7
              end:
                line: 1
                character: 10
            severity: ERROR
            message: Cannot find type `::Int`
            code: Ruby::RBSError
          - range:
              start:
                line: 2
                character: 14
              end:
                line: 2
                character: 17
            severity: ERROR
            message: Cannot find type `::Int`
            code: Ruby::RBSError
      YAML
    )
  end

  def test_nilq_unreachable
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          if 1.nil?
            123
          else
            123
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 0
              end:
                line: 1
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end

  def test_type_case__type_variable
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            def foo: [A] (A) -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Hello
            def foo(x)
              case x
              when Hash
                123
              when String
                123
              end
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_lambda__hint_is_untyped
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          a = _ = ->(x) { x + 1 }
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_safe_navigation_operator__or_hint
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Hello
            def foo: (Integer?) -> Integer
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Hello
            def foo(a)
              a&.then {|x| x.infinite? } || -1
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_type_check__elsif
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          x = nil #: Symbol?

          if x.is_a?(Integer)
            1
          elsif x.is_a?(String)
            2
          elsif x.is_a?(NilClass)
            3
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 3
                character: 0
              end:
                line: 3
                character: 2
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
          - range:
              start:
                line: 5
                character: 0
              end:
                line: 5
                character: 5
            severity: ERROR
            message: The branch is unreachable
            code: Ruby::UnreachableBranch
      YAML
    )
  end

  def test_untyped_nilp
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          a = _ = nil

          if a.nil?
            1
          else
            2
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_paren_conditional
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          a = [1].first
          b = [2].first

          if (a && b)
            a + b
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_self_constant
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class ConstantTest
            NAME: String
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class ConstantTest
            self::NAME
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_class_narrowing
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          module Foo
            def self.foo: () -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          klass = Class.new()

          if klass < Foo
            klass.foo()
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_calls_with_index_writer_methods
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class WithIndexWriter
            def []=: (String, String) -> Integer
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          obj = WithIndexWriter.new
          obj.[]=("hoge", "huga").foo
          obj&.[]=("hoge", "huga").foo
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 2
                character: 24
              end:
                line: 2
                character: 27
            severity: ERROR
            message: Type `::Integer` does not have method `foo`
            code: Ruby::NoMethod
          - range:
              start:
                line: 3
                character: 25
              end:
                line: 3
                character: 28
            severity: ERROR
            message: Type `(::Integer | nil)` does not have method `foo`
            code: Ruby::NoMethod
      YAML
    )
  end

  def test_underscore_opt_param
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          class Foo
            def foo: (?String, *untyped, **untyped) -> void

            def bar: () { (?String, *untyped, **untyped) -> void } -> void
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          class Foo
            def foo(_ = "", *_, **_)
              bar {|_ = "", *_, **_| }
            end

            def bar
            end
          end
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_rescue_assignment
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          begin
            x = 123
          rescue
            raise
          end

          x + 1
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_defined?
    run_type_check_test(
      signatures: {
      },
      code: {
        "a.rb" => <<~RUBY
          defined? foo
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end

  def test_string_match
    run_type_check_test(
      signatures: {},
      code: {
        "a.rb" => <<~RUBY
          "" =~ ""
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics:
          - range:
              start:
                line: 1
                character: 0
              end:
                line: 1
                character: 8
            severity: ERROR
            message: |-
              Cannot find compatible overloading of method `=~` of type `::String`
              Method types:
                def =~: (::Regexp) -> (::Integer | nil)
                      | [T] (::String::_MatchAgainst[::String, T]) -> T
            code: Ruby::UnresolvedOverloading
      YAML
    )
  end

  def test_big_union
    run_type_check_test(
      signatures: {
        "a.rbs" => <<~RBS
          # Extracted from aws-sdk
          class CreateFleetInstance
            attr_accessor instance_type: "a1.medium" | "a1.large" | "a1.xlarge" | "a1.2xlarge" | "a1.4xlarge" | "a1.metal" | "c1.medium" | "c1.xlarge" | "c3.large" | "c3.xlarge" | "c3.2xlarge" | "c3.4xlarge" | "c3.8xlarge" | "c4.large" | "c4.xlarge" | "c4.2xlarge" | "c4.4xlarge" | "c4.8xlarge" | "c5.large" | "c5.xlarge" | "c5.2xlarge" | "c5.4xlarge" | "c5.9xlarge" | "c5.12xlarge" | "c5.18xlarge" | "c5.24xlarge" | "c5.metal" | "c5a.large" | "c5a.xlarge" | "c5a.2xlarge" | "c5a.4xlarge" | "c5a.8xlarge" | "c5a.12xlarge" | "c5a.16xlarge" | "c5a.24xlarge" | "c5ad.large" | "c5ad.xlarge" | "c5ad.2xlarge" | "c5ad.4xlarge" | "c5ad.8xlarge" | "c5ad.12xlarge" | "c5ad.16xlarge" | "c5ad.24xlarge" | "c5d.large" | "c5d.xlarge" | "c5d.2xlarge" | "c5d.4xlarge" | "c5d.9xlarge" | "c5d.12xlarge" | "c5d.18xlarge" | "c5d.24xlarge" | "c5d.metal" | "c5n.large" | "c5n.xlarge" | "c5n.2xlarge" | "c5n.4xlarge" | "c5n.9xlarge" | "c5n.18xlarge" | "c5n.metal" | "c6g.medium" | "c6g.large" | "c6g.xlarge" | "c6g.2xlarge" | "c6g.4xlarge" | "c6g.8xlarge" | "c6g.12xlarge" | "c6g.16xlarge" | "c6g.metal" | "c6gd.medium" | "c6gd.large" | "c6gd.xlarge" | "c6gd.2xlarge" | "c6gd.4xlarge" | "c6gd.8xlarge" | "c6gd.12xlarge" | "c6gd.16xlarge" | "c6gd.metal" | "c6gn.medium" | "c6gn.large" | "c6gn.xlarge" | "c6gn.2xlarge" | "c6gn.4xlarge" | "c6gn.8xlarge" | "c6gn.12xlarge" | "c6gn.16xlarge" | "c6i.large" | "c6i.xlarge" | "c6i.2xlarge" | "c6i.4xlarge" | "c6i.8xlarge" | "c6i.12xlarge" | "c6i.16xlarge" | "c6i.24xlarge" | "c6i.32xlarge" | "c6i.metal" | "cc1.4xlarge" | "cc2.8xlarge" | "cg1.4xlarge" | "cr1.8xlarge" | "d2.xlarge" | "d2.2xlarge" | "d2.4xlarge" | "d2.8xlarge" | "d3.xlarge" | "d3.2xlarge" | "d3.4xlarge" | "d3.8xlarge" | "d3en.xlarge" | "d3en.2xlarge" | "d3en.4xlarge" | "d3en.6xlarge" | "d3en.8xlarge" | "d3en.12xlarge" | "dl1.24xlarge" | "f1.2xlarge" | "f1.4xlarge" | "f1.16xlarge" | "g2.2xlarge" | "g2.8xlarge" | "g3.4xlarge" | "g3.8xlarge" | "g3.16xlarge" | "g3s.xlarge" | "g4ad.xlarge" | "g4ad.2xlarge" | "g4ad.4xlarge" | "g4ad.8xlarge" | "g4ad.16xlarge" | "g4dn.xlarge" | "g4dn.2xlarge" | "g4dn.4xlarge" | "g4dn.8xlarge" | "g4dn.12xlarge" | "g4dn.16xlarge" | "g4dn.metal" | "g5.xlarge" | "g5.2xlarge" | "g5.4xlarge" | "g5.8xlarge" | "g5.12xlarge" | "g5.16xlarge" | "g5.24xlarge" | "g5.48xlarge" | "g5g.xlarge" | "g5g.2xlarge" | "g5g.4xlarge" | "g5g.8xlarge" | "g5g.16xlarge" | "g5g.metal" | "hi1.4xlarge" | "hpc6a.48xlarge" | "hs1.8xlarge" | "h1.2xlarge" | "h1.4xlarge" | "h1.8xlarge" | "h1.16xlarge" | "i2.xlarge" | "i2.2xlarge" | "i2.4xlarge" | "i2.8xlarge" | "i3.large" | "i3.xlarge" | "i3.2xlarge" | "i3.4xlarge" | "i3.8xlarge" | "i3.16xlarge" | "i3.metal" | "i3en.large" | "i3en.xlarge" | "i3en.2xlarge" | "i3en.3xlarge" | "i3en.6xlarge" | "i3en.12xlarge" | "i3en.24xlarge" | "i3en.metal" | "im4gn.large" | "im4gn.xlarge" | "im4gn.2xlarge" | "im4gn.4xlarge" | "im4gn.8xlarge" | "im4gn.16xlarge" | "inf1.xlarge" | "inf1.2xlarge" | "inf1.6xlarge" | "inf1.24xlarge" | "is4gen.medium" | "is4gen.large" | "is4gen.xlarge" | "is4gen.2xlarge" | "is4gen.4xlarge" | "is4gen.8xlarge" | "m1.small" | "m1.medium" | "m1.large" | "m1.xlarge" | "m2.xlarge" | "m2.2xlarge" | "m2.4xlarge" | "m3.medium" | "m3.large" | "m3.xlarge" | "m3.2xlarge" | "m4.large" | "m4.xlarge" | "m4.2xlarge" | "m4.4xlarge" | "m4.10xlarge" | "m4.16xlarge" | "m5.large" | "m5.xlarge" | "m5.2xlarge" | "m5.4xlarge" | "m5.8xlarge" | "m5.12xlarge" | "m5.16xlarge" | "m5.24xlarge" | "m5.metal" | "m5a.large" | "m5a.xlarge" | "m5a.2xlarge" | "m5a.4xlarge" | "m5a.8xlarge" | "m5a.12xlarge" | "m5a.16xlarge" | "m5a.24xlarge" | "m5ad.large" | "m5ad.xlarge" | "m5ad.2xlarge" | "m5ad.4xlarge" | "m5ad.8xlarge" | "m5ad.12xlarge" | "m5ad.16xlarge" | "m5ad.24xlarge" | "m5d.large" | "m5d.xlarge" | "m5d.2xlarge" | "m5d.4xlarge" | "m5d.8xlarge" | "m5d.12xlarge" | "m5d.16xlarge" | "m5d.24xlarge" | "m5d.metal" | "m5dn.large" | "m5dn.xlarge" | "m5dn.2xlarge" | "m5dn.4xlarge" | "m5dn.8xlarge" | "m5dn.12xlarge" | "m5dn.16xlarge" | "m5dn.24xlarge" | "m5dn.metal" | "m5n.large" | "m5n.xlarge" | "m5n.2xlarge" | "m5n.4xlarge" | "m5n.8xlarge" | "m5n.12xlarge" | "m5n.16xlarge" | "m5n.24xlarge" | "m5n.metal" | "m5zn.large" | "m5zn.xlarge" | "m5zn.2xlarge" | "m5zn.3xlarge" | "m5zn.6xlarge" | "m5zn.12xlarge" | "m5zn.metal" | "m6a.large" | "m6a.xlarge" | "m6a.2xlarge" | "m6a.4xlarge" | "m6a.8xlarge" | "m6a.12xlarge" | "m6a.16xlarge" | "m6a.24xlarge" | "m6a.32xlarge" | "m6a.48xlarge" | "m6g.metal" | "m6g.medium" | "m6g.large" | "m6g.xlarge" | "m6g.2xlarge" | "m6g.4xlarge" | "m6g.8xlarge" | "m6g.12xlarge" | "m6g.16xlarge" | "m6gd.metal" | "m6gd.medium" | "m6gd.large" | "m6gd.xlarge" | "m6gd.2xlarge" | "m6gd.4xlarge" | "m6gd.8xlarge" | "m6gd.12xlarge" | "m6gd.16xlarge" | "m6i.large" | "m6i.xlarge" | "m6i.2xlarge" | "m6i.4xlarge" | "m6i.8xlarge" | "m6i.12xlarge" | "m6i.16xlarge" | "m6i.24xlarge" | "m6i.32xlarge" | "m6i.metal" | "mac1.metal" | "p2.xlarge" | "p2.8xlarge" | "p2.16xlarge" | "p3.2xlarge" | "p3.8xlarge" | "p3.16xlarge" | "p3dn.24xlarge" | "p4d.24xlarge" | "r3.large" | "r3.xlarge" | "r3.2xlarge" | "r3.4xlarge" | "r3.8xlarge" | "r4.large" | "r4.xlarge" | "r4.2xlarge" | "r4.4xlarge" | "r4.8xlarge" | "r4.16xlarge" | "r5.large" | "r5.xlarge" | "r5.2xlarge" | "r5.4xlarge" | "r5.8xlarge" | "r5.12xlarge" | "r5.16xlarge" | "r5.24xlarge" | "r5.metal" | "r5a.large" | "r5a.xlarge" | "r5a.2xlarge" | "r5a.4xlarge" | "r5a.8xlarge" | "r5a.12xlarge" | "r5a.16xlarge" | "r5a.24xlarge" | "r5ad.large" | "r5ad.xlarge" | "r5ad.2xlarge" | "r5ad.4xlarge" | "r5ad.8xlarge" | "r5ad.12xlarge" | "r5ad.16xlarge" | "r5ad.24xlarge" | "r5b.large" | "r5b.xlarge" | "r5b.2xlarge" | "r5b.4xlarge" | "r5b.8xlarge" | "r5b.12xlarge" | "r5b.16xlarge" | "r5b.24xlarge" | "r5b.metal" | "r5d.large" | "r5d.xlarge" | "r5d.2xlarge" | "r5d.4xlarge" | "r5d.8xlarge" | "r5d.12xlarge" | "r5d.16xlarge" | "r5d.24xlarge" | "r5d.metal" | "r5dn.large" | "r5dn.xlarge" | "r5dn.2xlarge" | "r5dn.4xlarge" | "r5dn.8xlarge" | "r5dn.12xlarge" | "r5dn.16xlarge" | "r5dn.24xlarge" | "r5dn.metal" | "r5n.large" | "r5n.xlarge" | "r5n.2xlarge" | "r5n.4xlarge" | "r5n.8xlarge" | "r5n.12xlarge" | "r5n.16xlarge" | "r5n.24xlarge" | "r5n.metal" | "r6g.medium" | "r6g.large" | "r6g.xlarge" | "r6g.2xlarge" | "r6g.4xlarge" | "r6g.8xlarge" | "r6g.12xlarge" | "r6g.16xlarge" | "r6g.metal" | "r6gd.medium" | "r6gd.large" | "r6gd.xlarge" | "r6gd.2xlarge" | "r6gd.4xlarge" | "r6gd.8xlarge" | "r6gd.12xlarge" | "r6gd.16xlarge" | "r6gd.metal" | "r6i.large" | "r6i.xlarge" | "r6i.2xlarge" | "r6i.4xlarge" | "r6i.8xlarge" | "r6i.12xlarge" | "r6i.16xlarge" | "r6i.24xlarge" | "r6i.32xlarge" | "r6i.metal" | "t1.micro" | "t2.nano" | "t2.micro" | "t2.small" | "t2.medium" | "t2.large" | "t2.xlarge" | "t2.2xlarge" | "t3.nano" | "t3.micro" | "t3.small" | "t3.medium" | "t3.large" | "t3.xlarge" | "t3.2xlarge" | "t3a.nano" | "t3a.micro" | "t3a.small" | "t3a.medium" | "t3a.large" | "t3a.xlarge" | "t3a.2xlarge" | "t4g.nano" | "t4g.micro" | "t4g.small" | "t4g.medium" | "t4g.large" | "t4g.xlarge" | "t4g.2xlarge" | "u-6tb1.56xlarge" | "u-6tb1.112xlarge" | "u-9tb1.112xlarge" | "u-12tb1.112xlarge" | "u-6tb1.metal" | "u-9tb1.metal" | "u-12tb1.metal" | "u-18tb1.metal" | "u-24tb1.metal" | "vt1.3xlarge" | "vt1.6xlarge" | "vt1.24xlarge" | "x1.16xlarge" | "x1.32xlarge" | "x1e.xlarge" | "x1e.2xlarge" | "x1e.4xlarge" | "x1e.8xlarge" | "x1e.16xlarge" | "x1e.32xlarge" | "x2iezn.2xlarge" | "x2iezn.4xlarge" | "x2iezn.6xlarge" | "x2iezn.8xlarge" | "x2iezn.12xlarge" | "x2iezn.metal" | "x2gd.medium" | "x2gd.large" | "x2gd.xlarge" | "x2gd.2xlarge" | "x2gd.4xlarge" | "x2gd.8xlarge" | "x2gd.12xlarge" | "x2gd.16xlarge" | "x2gd.metal" | "z1d.large" | "z1d.xlarge" | "z1d.2xlarge" | "z1d.3xlarge" | "z1d.6xlarge" | "z1d.12xlarge" | "z1d.metal" | "x2idn.16xlarge" | "x2idn.24xlarge" | "x2idn.32xlarge" | "x2iedn.xlarge" | "x2iedn.2xlarge" | "x2iedn.4xlarge" | "x2iedn.8xlarge" | "x2iedn.16xlarge" | "x2iedn.24xlarge" | "x2iedn.32xlarge" | "c6a.large" | "c6a.xlarge" | "c6a.2xlarge" | "c6a.4xlarge" | "c6a.8xlarge" | "c6a.12xlarge" | "c6a.16xlarge" | "c6a.24xlarge" | "c6a.32xlarge" | "c6a.48xlarge" | "c6a.metal" | "m6a.metal" | "i4i.large" | "i4i.xlarge" | "i4i.2xlarge" | "i4i.4xlarge" | "i4i.8xlarge" | "i4i.16xlarge" | "i4i.32xlarge" | "i4i.metal" | "x2idn.metal" | "x2iedn.metal" | "c7g.medium" | "c7g.large" | "c7g.xlarge" | "c7g.2xlarge" | "c7g.4xlarge" | "c7g.8xlarge" | "c7g.12xlarge" | "c7g.16xlarge" | "mac2.metal" | "c6id.large" | "c6id.xlarge" | "c6id.2xlarge" | "c6id.4xlarge" | "c6id.8xlarge" | "c6id.12xlarge" | "c6id.16xlarge" | "c6id.24xlarge" | "c6id.32xlarge" | "c6id.metal" | "m6id.large" | "m6id.xlarge" | "m6id.2xlarge" | "m6id.4xlarge" | "m6id.8xlarge" | "m6id.12xlarge" | "m6id.16xlarge" | "m6id.24xlarge" | "m6id.32xlarge" | "m6id.metal" | "r6id.large" | "r6id.xlarge" | "r6id.2xlarge" | "r6id.4xlarge" | "r6id.8xlarge" | "r6id.12xlarge" | "r6id.16xlarge" | "r6id.24xlarge" | "r6id.32xlarge" | "r6id.metal" | "r6a.large" | "r6a.xlarge" | "r6a.2xlarge" | "r6a.4xlarge" | "r6a.8xlarge" | "r6a.12xlarge" | "r6a.16xlarge" | "r6a.24xlarge" | "r6a.32xlarge" | "r6a.48xlarge" | "r6a.metal" | "p4de.24xlarge" | "u-3tb1.56xlarge" | "u-18tb1.112xlarge" | "u-24tb1.112xlarge" | "trn1.2xlarge" | "trn1.32xlarge" | "hpc6id.32xlarge" | "c6in.large" | "c6in.xlarge" | "c6in.2xlarge" | "c6in.4xlarge" | "c6in.8xlarge" | "c6in.12xlarge" | "c6in.16xlarge" | "c6in.24xlarge" | "c6in.32xlarge" | "m6in.large" | "m6in.xlarge" | "m6in.2xlarge" | "m6in.4xlarge" | "m6in.8xlarge" | "m6in.12xlarge" | "m6in.16xlarge" | "m6in.24xlarge" | "m6in.32xlarge" | "m6idn.large" | "m6idn.xlarge" | "m6idn.2xlarge" | "m6idn.4xlarge" | "m6idn.8xlarge" | "m6idn.12xlarge" | "m6idn.16xlarge" | "m6idn.24xlarge" | "m6idn.32xlarge" | "r6in.large" | "r6in.xlarge" | "r6in.2xlarge" | "r6in.4xlarge" | "r6in.8xlarge" | "r6in.12xlarge" | "r6in.16xlarge" | "r6in.24xlarge" | "r6in.32xlarge" | "r6idn.large" | "r6idn.xlarge" | "r6idn.2xlarge" | "r6idn.4xlarge" | "r6idn.8xlarge" | "r6idn.12xlarge" | "r6idn.16xlarge" | "r6idn.24xlarge" | "r6idn.32xlarge" | "c7g.metal" | "m7g.medium" | "m7g.large" | "m7g.xlarge" | "m7g.2xlarge" | "m7g.4xlarge" | "m7g.8xlarge" | "m7g.12xlarge" | "m7g.16xlarge" | "m7g.metal" | "r7g.medium" | "r7g.large" | "r7g.xlarge" | "r7g.2xlarge" | "r7g.4xlarge" | "r7g.8xlarge" | "r7g.12xlarge" | "r7g.16xlarge" | "r7g.metal" | "c6in.metal" | "m6in.metal" | "m6idn.metal" | "r6in.metal" | "r6idn.metal" | "inf2.xlarge" | "inf2.8xlarge" | "inf2.24xlarge" | "inf2.48xlarge" | "trn1n.32xlarge" | "i4g.large" | "i4g.xlarge" | "i4g.2xlarge" | "i4g.4xlarge" | "i4g.8xlarge" | "i4g.16xlarge" | "hpc7g.4xlarge" | "hpc7g.8xlarge" | "hpc7g.16xlarge" | "c7gn.medium" | "c7gn.large" | "c7gn.xlarge" | "c7gn.2xlarge" | "c7gn.4xlarge" | "c7gn.8xlarge" | "c7gn.12xlarge" | "c7gn.16xlarge" | "p5.48xlarge" | "m7i.large" | "m7i.xlarge" | "m7i.2xlarge" | "m7i.4xlarge" | "m7i.8xlarge" | "m7i.12xlarge" | "m7i.16xlarge" | "m7i.24xlarge" | "m7i.48xlarge" | "m7i-flex.large" | "m7i-flex.xlarge" | "m7i-flex.2xlarge" | "m7i-flex.4xlarge" | "m7i-flex.8xlarge" | "m7a.medium" | "m7a.large" | "m7a.xlarge" | "m7a.2xlarge" | "m7a.4xlarge" | "m7a.8xlarge" | "m7a.12xlarge" | "m7a.16xlarge" | "m7a.24xlarge" | "m7a.32xlarge" | "m7a.48xlarge" | "m7a.metal-48xl" | "hpc7a.12xlarge" | "hpc7a.24xlarge" | "hpc7a.48xlarge" | "hpc7a.96xlarge" | "c7gd.medium" | "c7gd.large" | "c7gd.xlarge" | "c7gd.2xlarge" | "c7gd.4xlarge" | "c7gd.8xlarge" | "c7gd.12xlarge" | "c7gd.16xlarge" | "m7gd.medium" | "m7gd.large" | "m7gd.xlarge" | "m7gd.2xlarge" | "m7gd.4xlarge" | "m7gd.8xlarge" | "m7gd.12xlarge" | "m7gd.16xlarge" | "r7gd.medium" | "r7gd.large" | "r7gd.xlarge" | "r7gd.2xlarge" | "r7gd.4xlarge" | "r7gd.8xlarge" | "r7gd.12xlarge" | "r7gd.16xlarge" | "r7a.medium" | "r7a.large" | "r7a.xlarge" | "r7a.2xlarge" | "r7a.4xlarge" | "r7a.8xlarge" | "r7a.12xlarge" | "r7a.16xlarge" | "r7a.24xlarge" | "r7a.32xlarge" | "r7a.48xlarge" | "c7i.large" | "c7i.xlarge" | "c7i.2xlarge" | "c7i.4xlarge" | "c7i.8xlarge" | "c7i.12xlarge" | "c7i.16xlarge" | "c7i.24xlarge" | "c7i.48xlarge" | "mac2-m2pro.metal" | "r7iz.large" | "r7iz.xlarge" | "r7iz.2xlarge" | "r7iz.4xlarge" | "r7iz.8xlarge" | "r7iz.12xlarge" | "r7iz.16xlarge" | "r7iz.32xlarge" | "c7a.medium" | "c7a.large" | "c7a.xlarge" | "c7a.2xlarge" | "c7a.4xlarge" | "c7a.8xlarge" | "c7a.12xlarge" | "c7a.16xlarge" | "c7a.24xlarge" | "c7a.32xlarge" | "c7a.48xlarge" | "c7a.metal-48xl" | "r7a.metal-48xl" | "r7i.large" | "r7i.xlarge" | "r7i.2xlarge" | "r7i.4xlarge" | "r7i.8xlarge" | "r7i.12xlarge" | "r7i.16xlarge" | "r7i.24xlarge" | "r7i.48xlarge" | "dl2q.24xlarge" | "mac2-m2.metal" | "i4i.12xlarge" | "i4i.24xlarge" | "c7i.metal-24xl" | "c7i.metal-48xl" | "m7i.metal-24xl" | "m7i.metal-48xl" | "r7i.metal-24xl" | "r7i.metal-48xl" | "r7iz.metal-16xl" | "r7iz.metal-32xl"
          end
        RBS
      },
      code: {
        "a.rb" => <<~RUBY
          CreateFleetInstance.new.instance_type.size
        RUBY
      },
      expectations: <<~YAML
        ---
        - file: a.rb
          diagnostics: []
      YAML
    )
  end
end
