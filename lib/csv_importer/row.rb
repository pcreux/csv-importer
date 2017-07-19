module CSVImporter
  # A Row from the CSV file.
  #
  # Using the header, the model_klass and the identifier it builds the model
  # to be persisted.
  class Row
    include Virtus.model

    attribute :header, Header
    attribute :row_array, Array[String]
    attribute :model_klass
    attribute :identifiers, Array[Symbol]
    attribute :after_build_blocks, Array[Proc], default: []
    attribute :skip, Boolean, default: false

    # The model to be persisted
    def model
      @model ||= begin
        model = find_or_build_model

        set_attributes(model)

        after_build_blocks.each { |block| instance_exec(model, &block) }
        model
      end
    end

    # A hash with this row's attributes
    def csv_attributes
      @csv_attributes ||= Hash[header.column_names.zip(row_array)]
    end

    # Set attributes
    def set_attributes(model)
      header.columns.each do |column|
        value = csv_attributes[column.name]
        begin
          value = value.dup if value
        rescue TypeError
          # can't dup Symbols, Integer etc...
        end

        column_definition = column.definition
        next if column_definition.nil?

        set_attribute(model, column_definition, value)
      end

      model
    end

    # Set the attribute using the column_definition and the csv_value
    def set_attribute(model, column_definition, csv_value)
      converter = Converter.infer(column_definition.to)
      converter.convert(csv_value, model, column_definition.attribute)

      model
    end

    # Error from the model mapped back to the CSV header if we can
    def errors
      Hash[
        model.errors.map do |attribute, errors|
          if column_name = header.column_name_for_model_attribute(attribute)
            [column_name, errors]
          else
            [attribute, errors]
          end
        end
      ]
    end

    def find_or_build_model
      find_model || build_model
    end

    def find_model
      return nil if identifiers.empty?

      model = build_model
      set_attributes(model)
      query = Hash[
        identifiers.map { |identifier| [ identifier, model.public_send(identifier) ] }
      ]
      model_klass.find_by(query)
    end

    def build_model
      model_klass.new
    end

    def skip!
      self.skip = true
    end
  end
end
