module CSVImporter
  # A Column from a CSV file with a `name` (from the csv file) and a matching
  # `ColumnDefinition` if any.
  class Column
    include Virtus.model

    attribute :name, String
    attribute :definition, ColumnDefinition
    attribute :rank, Integer, default: 0
  end
end
