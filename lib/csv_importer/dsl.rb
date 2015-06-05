module CSVImporter
  # This Dsl extends a class that includes CSVImporter
  # It is a thin proxy to the Config object
  module Dsl
    def model(model_klass)
      csv_importer_config.model = model_klass
    end

    def column(name, options={})
      csv_importer_config.column_definitions << options.merge(name: name)
    end

    def identifier(identifier)
      csv_importer_config.identifier = identifier
    end

    def when_invalid(action)
      csv_importer_config.when_invalid = action
    end
  end
end
