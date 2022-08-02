module CSVImporter

  # The CSV Header
  class Header
    include Virtus.model

    attribute :column_definitions, Array[ColumnDefinition]
    attribute :column_names, Array[String]

    def columns
      column_names.map do |column_name|
        # ensure column name escapes invisible characters
        column_name = column_name.gsub(/[^[:print:]]/, '')

        Column.new(
          name: column_name,
          definition: find_column_definition(column_name)
        )
      end
    end

    def column_name_for_model_attribute(attribute)
      if column = columns.find { |column| column.definition.attribute == attribute if column.definition }
        column.name
      end
    end

    def valid?
      missing_required_columns.empty?
    end

    # Returns Array[String]
    def required_columns
      column_definitions.select(&:required?).map(&:name)
    end

    # Returns Array[String]
    def extra_columns
      columns.reject(&:definition).map(&:name).map(&:to_s)
    end

    # Returns Array[String]
    def missing_required_columns
      (column_definitions.select(&:required?) - columns.map(&:definition)).map(&:name).map(&:to_s)
    end

    # Returns Array[String]
    def missing_columns
      (column_definitions - columns.map(&:definition)).map(&:name).map(&:to_s)
    end

    private

    def find_column_definition(name)
      column_definitions.find do |column_definition|
        column_definition.match?(name)
      end
    end

    def column_definition_names
      column_definitions.map(&:name).map(&:to_s)
    end
  end
end
