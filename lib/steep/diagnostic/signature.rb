module Steep
  module Diagnostic
    module Signature
      class Base
        include Helper

        attr_reader :location

        def initialize(location:)
          @location = location
        end

        def header_line
          StringIO.new.tap do |io|
            puts io
          end.string
        end

        def detail_lines
          nil
        end

        def diagnostic_code
          "Ruby::#{error_name}"
        end

        def path
          location.buffer.name
        end
      end

      class SyntaxError < Base
        attr_reader :exception

        def initialize(exception, location:)
          super(location: location)
          @exception = exception
        end

        def header_line
          "Syntax error: #{exception.message}"
        end
      end

      class DuplicatedDeclaration < Base
        attr_reader :type_name

        def initialize(type_name:, location:)
          super(location: location)
          @type_name = type_name
        end

        def header_line
          "Declaration of `#{type_name}` is duplicated"
        end
      end

      class UnknownTypeName < Base
        attr_reader :name

        def initialize(name:, location:)
          super(location: location)
          @name = name
        end

        def header_line
          "Cannot find type `#{name}`"
        end
      end

      class InvalidTypeApplication < Base
        attr_reader :name
        attr_reader :args
        attr_reader :params

        def initialize(name:, args:, params:, location:)
          super(location: location)
          @name = name
          @args = args
          @params = params
        end

        def header_line
          case
          when params.empty?
            "Type `#{name}` is not generic but used as a generic type with #{args.size} arguments"
          when args.empty?
            "Type `#{name}` is generic but used as a non generic type"
          else
            "Type `#{name}` expects #{params.size} arguments, but #{args.size} arguments are given"
          end
        end
      end

      class InvalidMethodOverload < Base
        attr_reader :class_name
        attr_reader :method_name

        def initialize(class_name:, method_name:, location:)
          super(location: location)
          @class_name = class_name
          @method_name = method_name
        end

        def header_line
          "Cannot find a non-overloading definition of `#{method_name}` in `#{class_name}`"
        end
      end

      class UnknownMethodAlias < Base
        attr_reader :class_name
        attr_reader :method_name

        def initialize(class_name:, method_name:, location:)
          super(location: location)
          @class_name = class_name
          @method_name = method_name
        end

        def header_line
          "Cannot find the original method `#{method_name}` in `#{class_name}`"
        end
      end

      class DuplicatedMethodDefinition < Base
        attr_reader :class_name
        attr_reader :method_name

        def initialize(class_name:, method_name:, location:)
          super(location: location)
          @class_name = class_name
          @method_name = method_name
        end

        def header_line
          "Non-overloading method definition of `#{method_name}` in `#{class_name}` cannot be duplicated"
        end
      end

      class RecursiveAlias < Base
        attr_reader :class_name
        attr_reader :names
        attr_reader :location

        def initialize(class_name:, names:, location:)
          super(location: location)
          @class_name = class_name
          @names = names
        end

        def header_line
          "Circular method alias is detected in `#{class_name}`: #{names.join(" -> ")}"
        end
      end

      class RecursiveAncestor < Base
        attr_reader :ancestors

        def initialize(ancestors:, location:)
          super(location: location)
          @ancestors = ancestors
        end

        def header_line
          names = ancestors.map do |ancestor|
            case ancestor
            when RBS::Definition::Ancestor::Singleton
              "singleton(#{ancestor.name})"
            when RBS::Definition::Ancestor::Instance
              if ancestor.args.empty?
                ancestor.name.to_s
              else
                "#{ancestor.name}[#{ancestor.args.join(", ")}]"
              end
            end
          end

          "Circular inheritance/mix-in is detected: #{names.join(" <: ")}"
        end
      end

      class SuperclassMismatch < Base
        attr_reader :name

        def initialize(name:, location:)
          super(location: location)
          @name = name
        end

        def header_line
          "Different superclasses are specified for `#{name}`"
        end
      end

      class GenericParameterMismatch < Base
        attr_reader :name

        def initialize(name:, location:)
          super(location: location)
          @name = name
        end

        def header_line
          "Different generic parameters are specified across definitions of `#{name}`"
        end
      end

      class InvalidVarianceAnnotation < Base
        attr_reader :name
        attr_reader :param

        def initialize(name:, param:, location:)
          super(location: location)
          @name = name
          @param = param
        end

        def header_line
          "The variance of type parameter `#{param.name}` is #{param.variance}, but used in incompatible position here"
        end
      end
    end
  end
end
