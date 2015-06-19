require "csv"
require "virtus"

require "csv_importer/version"
require "csv_importer/csv_reader"
require "csv_importer/column_definition"
require "csv_importer/column"
require "csv_importer/header"
require "csv_importer/row"
require "csv_importer/report"
require "csv_importer/report_message"
require "csv_importer/runner"
require "csv_importer/config"
require "csv_importer/dsl"

# A class that includes CSVImporter inherit its DSL and methods.
#
# Example:
#   class ImportUserCSV
#     include CSVImporter
#
#     model User
#
#     column :email
#   end
#
#   report = ImportUserCSV.new(file: my_csv).run!
#   puts report.message
#
module CSVImporter
  class Error < StandardError; end

  def self.included(klass)
    klass.extend(Dsl)
    klass.define_singleton_method(:csv_importer_config) do
      @csv_importer_config ||= Config.new
    end
  end

  # Defines the path, file or content of the csv file.
  # Also allows you to overwrite the configuration at runtime.
  #
  # Example:
  #
  #   .new(file: my_csv_file)
  #   .new(path: "subscribers.csv", model: newsletter.subscribers)
  #
  def initialize(*args)
    @csv = CSVReader.new(*args)
    @config = self.class.csv_importer_config.dup
    @config.attributes = args.last
    @report = Report.new
  end

  attr_reader :csv, :report, :config

  # Initialize and return the `Header` for the current CSV file
  def header
    @header ||= Header.new(column_definitions: config.column_definitions, column_names: csv.header)
  end

  # Initialize and return the `Row`s for the current CSV file
  def rows
    csv.rows.map do |row_array|
      Row.new(header: header, row_array: row_array, model_klass: config.model,
              identifier: config.identifier, after_build: config.after_build)
    end
  end

  def valid_header?
    if @report.pending?
      if header.valid?
        @report = Report.new(status: :pending, extra_columns: header.extra_columns)
      else
        @report = Report.new(status: :invalid_header, missing_columns: header.missing_required_columns, extra_columns: header.extra_columns)
      end
    end

    header.valid?
  end

  # Run the import. Return a Report.
  def run!
    if valid_header?
      @report = Runner.call(rows: rows, when_invalid: config.when_invalid)
    else
      @report
    end
  rescue CSV::MalformedCSVError => e
    @report = Report.new(status: :invalid_csv_file, parser_error: e.message)
  end
end

