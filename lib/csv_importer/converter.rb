module CSVImporter
  class Converter
    DEFAULT = ->(value) { value }

    def self.infer(proc_or_class)
      return ProcConverter.new(proc_or_class) if proc_or_class.is_a?(Proc)
      return proc_or_class.new if proc_or_class.is_a?(Class)

      Converter.new
    end

    def parse(csv_value)
      csv_value
    end

    def convert(csv_value, model, attribute_name)
      value = parse(csv_value)

      assign(model, attribute_name, value)
    end

    private

    def assign(model, attribute_name, value)
      model.public_send("#{ attribute_name }=", value)
    end

    class ProcConverter < self
      def initialize(block = DEFAULT)
        @proc = block
      end

      def parse(csv_value)
        case @proc.arity
        when 1 then @proc.call(csv_value)
        else
          csv_value
        end
      end

      def convert(csv_value, model, attribute_name)
        case @proc.arity
        when 2 then @proc.call(csv_value, model)
        else
          super
        end
      end
    end
  end
end
