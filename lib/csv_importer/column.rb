module CSVImporter
  # A Column from a CSV file with a `name` (from the csv file) and a matching
  # `ColumnDefinition` if any.
  class Column
    include Virtus.model

    attribute :name, String
    attribute :definition, ColumnDefinition

    # Return the data associated to the name (column_name[data])
    def data
      match = /.*\[(.*)\]/.match(name)
      match[1] if match
    end

  end
end
