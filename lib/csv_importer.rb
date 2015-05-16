require "csv_importer/version"
require "csv"
require "virtus"

module CSVImporter
  class CSVReader
    include Virtus.model

    attribute :content, String

    def csv_rows
      @csv_rows ||= CSV.parse(content)
    end

    def header
      @header ||= csv_rows.first
    end

    def rows
      @rows ||= csv_rows[1..-1]
    end
  end

  class ColumnDefinition
    include Virtus.model

    attribute :name, Symbol
    attribute :to
    attribute :required, Boolean

    def attribute
      to || name
    end
  end

  class Header
    include Virtus.model

    attribute :columns_config, Array[ColumnDefinition]
    attribute :row, Array[String]

    def columns
      row.map { |cell| cell.to_sym if cell }
    end

    def column_name_for(attribute)
      if column = columns_config.select { |column| column.attribute == attribute }.first
        column.name
      end
    end

    def valid?
      missing_required_columns.empty?
    end

    def required_columns
      columns_config.select { |c| c.required? }.map(&:name)
    end

    def extra_columns
      columns - columns_config.map(&:name)
    end

    def missing_required_columns
      required_columns - columns
    end

    def missing_columns
      columns_config.map(&:name) - columns
    end
  end

  class Row
    include Virtus.model

    attribute :header, Header
    attribute :row_array, Array[String]
    attribute :model_klass
    attribute :identifier

    def model
      @model ||= begin
        model = if identifier
          value = csv_attributes[header.column_name_for(identifier)]
          model_klass.public_send("find_by_#{identifier}", value)
        end

        model ||= model_klass.new
        set_attributes(model)
        model
      end
    end

    def csv_attributes
      @csv_attributes ||= Hash[header.columns.zip(row_array)]
    end

    def set_attributes(model)
      header.columns_config.each do |column|
        csv_value = csv_attributes[column.name]
        attribute = column.attribute
        if attribute.is_a?(Proc)
          attribute.call(csv_value, model)
        else
          model.public_send("#{attribute}=", csv_value)
        end
      end
    end

    def errors
      Hash[
        model.errors.map do |attribute, errors|
          if column_name = header.column_name_for(attribute)
            [column_name, errors]
          else
            [attribute, errors]
          end
        end
      ]
    end
  end

  class Report
    include Virtus.model

    attribute :created_rows, Array[Row]
    attribute :updated_rows, Array[Row]
    attribute :failed_to_create_rows, Array[Row]
    attribute :failed_to_update_rows, Array[Row]

    def valid_rows
      created_rows + updated_rows
    end

    def invalid_rows
      failed_to_create_rows + failed_to_update_rows
    end

    def all_rows
      valid_rows + invalid_rows
    end
  end

  class Runner
    def self.call(*args)
      new(*args).call
    end

    include Virtus.model

    attribute :rows, Array[Row]

    def call
      report = Report.new

      rows.each do |row|
        if row.model.persisted?
          if row.model.save
            report.updated_rows << row
          else
            report.failed_to_update_rows << row
          end
        else
          if row.model.save
            report.created_rows << row
          else
            report.failed_to_create_rows << row
          end
        end
      end

      report
    end
  end

  class Config
    include Virtus.model

    attribute :model
    attribute :columns, Array[ColumnDefinition], default: proc { [] }
    attribute :identifier, Symbol
    attribute :when_invalid, Symbol, default: proc { :skip }
  end

  class Error < StandardError
  end

  module Dsl
    def model(model_klass)
      csv_importer_config.model = model_klass
    end

    def column(name, options={})
      csv_importer_config.columns << options.merge(name: name)
    end

    def identifier(identifier)
      csv_importer_config.identifier = identifier
    end

    def when_invalid(action)
      csv_importer_config.when_invalid = action
    end
  end
end

module CSVImporter
  def self.included(klass)
    klass.extend(Dsl)
    klass.define_singleton_method(:csv_importer_config) do
      @csv_importer_config ||= Config.new
    end
  end

  def initialize(*args)
    @csv = CSVReader.new(*args)
  end

  attr_reader :csv, :report

  def header
    @header ||= Header.new(columns_config: config.columns, row: csv.header)
  end

  def config
    self.class.csv_importer_config
  end

  def rows
    csv.rows.map { |row_array| Row.new(header: header, row_array: row_array,
                                       model_klass: config.model, identifier: config.identifier) }
  end

  def run!
    unless header.valid?
      raise Error,
        "The following columns are required: #{header.missing_required_columns.join(', ')}"
    end

    @report = Runner.call(rows: rows)
  end

end
