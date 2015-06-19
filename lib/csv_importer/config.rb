module CSVImporter
  # The configuration of a CSVImporter
  class Config
    include Virtus.model

    attribute :model
    attribute :column_definitions, Array[ColumnDefinition], default: proc { [] }
    attribute :identifier, Symbol
    attribute :when_invalid, Symbol, default: proc { :skip }
    attribute :after_build, Proc, default: proc { ->(model) {} }
  end
end

