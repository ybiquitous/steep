module Steep
  module Interface
    class Shape
      class Entry
        attr_reader :method_types

        def initialize(method_types:)
          @method_types = method_types
        end

        def to_s
          "{ #{method_types.join(" || ")} }"
        end
      end

      class UnionEntry
        attr_reader :entries, :subtyping

        def initialize(entries:, subtyping:)
          @entries = entries
          @subtyping = subtyping
        end

        def to_s
          "UnionEntry(" + entries.join(" | ") + ")"
        end

        def resolve
          entries.inject do |m1, m2|
            types1 = m1.method_types
            types2 = m2.method_types

            if types1 == types2
              if types1.map {|type| type.method_decls.to_a }.to_set == types2.map {|type| type.method_decls.to_a }.to_set
                next m1
              end
            end

            method_types = {} #: Hash[MethodType, true]

            types1.each do |type1|
              types2.each do |type2|
                if type1 == type2
                  method_types[type1.with(method_decls: type1.method_decls + type2.method_decls)] = true
                else
                  if type = MethodType.union(type1, type2, subtyping)
                    method_types[type] = true
                  end
                end
              end
            end

            return if method_types.empty?

            Interface::Shape::Entry.new(method_types: method_types.keys)
          end
        end
      end

      class Methods
        attr_reader :substs, :methods, :resolved_methods

        include Enumerable

        def initialize(substs:, methods:)
          @substs = substs
          @methods = methods
          @resolved_methods = {}
        end

        def key?(name)
          case methods.fetch(name, nil)
          when UnionEntry
            self[name] ? true : false
          when Entry
            true
          else
            false
          end
        end

        def []=(name, entry)
          resolved_methods.delete(name)
          methods[name] = entry
        end

        def [](name)
          return nil unless methods.key?(name)

          resolved_methods.fetch(name) do
            entry = methods.fetch(name)

            if entry.is_a?(UnionEntry)
              entry = entry.resolve
            else
              1+2
            end

            resolved_methods[name] =
              if entry
                Entry.new(
                  method_types: entry.method_types.map do |method_type|
                    method_type.subst(subst)
                  end
                )
              else
                nil
              end
          end
        end

        def fetch(name)
          self[name] || raise("Unknown method: #{name}")
        end

        def each(&block)
          if block
            methods.each_key do |name|
              entry = self[name] or raise
              yield [name, entry]
            end
          else
            enum_for :each
          end
        end

        def each_name(&block)
          if block
            methods.each_key do |key|
              if key?(key)
                yield key
              end
            end
          else
            enum_for :each_name
          end
        end

        def subst
          @subst ||= begin
            substs.each_with_object(Substitution.empty) do |s, ss|
              ss.merge!(s, overwrite: true)
            end
          end
        end

        def push_substitution(subst)
          Methods.new(substs: [*substs, subst], methods: methods)
        end

        def merge!(other)
          other.each do |name, entry|
            methods[name] = entry
          end
        end
      end

      attr_reader :type
      attr_reader :methods

      def initialize(type:, private:, methods: nil)
        @type = type
        @private = private
        @methods = methods || Methods.new(substs: [], methods: {})
      end

      def to_s
        "#<#{self.class.name}: type=#{type}, private?=#{@private}, methods={#{methods.each_name.sort.join(", ")}}"
      end

      def update(type: self.type, methods: self.methods)
        _ = self.class.new(type: type, private: private?, methods: methods)
      end

      def subst(s, type: nil)
        ty =
          if type
            type
          else
            self.type.subst(s)
          end

        Shape.new(type: ty, private: private?, methods: methods.push_substitution(s))
      end

      def private?
        @private
      end

      def public?
        !private?
      end
    end
  end
end
