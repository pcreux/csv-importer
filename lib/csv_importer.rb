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

   # Setup DSL and config object
  def self.included(klass)
    klass.extend(Dsl)
    klass.define_singleton_method(:config) do
      @config ||= Config.new
    end
  end

  # Instance level config will run against this configurator
  class Configurator < Struct.new(:config)
    include Dsl
  end


  # Defines the path, file or content of the csv file.
  # Also allows you to overwrite the configuration at runtime.
  #
  # Example:
  #
  #   .new(file: my_csv_file)
  #   .new(path: "subscribers.csv", model: newsletter.subscribers)
  #
  def initialize(*args, &block)
    @csv = CSVReader.new(*args)
    @config = self.class.config.dup
    @config.attributes = args.last
    @report = Report.new
    Configurator.new(@config).instance_exec(&block) if block
  end

  attr_reader :csv, :report, :config

  # Initialize and return the `Header` for the current CSV file
  def header
    @header ||= Header.new(column_definitions: config.column_definitions, column_names: csv.header)
  end

  # Initialize and return the `Row`s for the current CSV file
  def rows
    csv.rows.map.with_index(2) do |row_array, line_number|
      Row.new(header: header, line_number: line_number, row_array: row_array, model_klass: config.model,
              identifiers: config.identifiers, after_build_blocks: config.after_build_blocks,
              after_set_attributes_blocks: config.after_set_attributes_blocks,
              default_values: config.default_values)
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
  rescue CSV::MalformedCSVError => e
    @report = Report.new(status: :invalid_csv_file, parser_error: e.message)
    false
  end

  # Run the import. Return a Report.
  def run!
    if valid_header?
      @report = Runner.call(rows: rows, when_invalid: config.when_invalid,
                            after_save_blocks: config.after_save_blocks, report: @report)
    else
      @report
    end
  rescue CSV::MalformedCSVError => e
    @report = Report.new(status: :invalid_csv_file, parser_error: e.message)
  end
end
