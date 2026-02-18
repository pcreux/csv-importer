module CSVImporter
  # A Column from a CSV file with a `name` (from the csv file) and a matching
  # `ColumnDefinition` if any.
  class Column
    attr_reader :name, :definition

    def initialize(name:, definition: nil)
      @name = name
      @definition = definition
    end
  end
end
