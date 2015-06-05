require "csv_importer/version"
require "csv"
require "virtus"

module CSVImporter

  # Reads, sanitize and parse a CSV file
  class CSVReader
    include Virtus.model

    attribute :content, String
    attribute :file # IO
    attribute :path, String

    def csv_rows
      @csv_rows ||= sanitize_cells(CSV.parse(sanitize_content(read_content)))
    end

    # Returns the header as an Array of Strings
    def header
      @header ||= csv_rows.first
    end

    # Returns the rows as an Array of Arrays of Strings
    def rows
      @rows ||= csv_rows[1..-1]
    end

    private

    def read_content
      if content.present?
        content
      elsif file.present?
        file.read
      elsif path.present?
        File.open(path).read
      else
        raise Error, "Please provide content, file, or path"
      end
    end

    # Strip cells
    def sanitize_cells(rows)
      rows.map do |cells|
        cells.map do |cell|
          cell.strip if cell
        end
      end
    end

    # Replaces windows line separators with "\n"
    def sanitize_content(csv_content)
      csv_content.gsub(/\r\r?\n?/, "\n")
    end
  end

  # Define a column. Called from the DSL via `column.
  #
  # Examples
  #
  #   # the csv column "email" will be assigned to the `email` attribute
  #   column :email
  #
  #   # the csv column matching /email/i will be assigned to the `email` attribute
  #   column :email, as: /email/i
  #
  #   # the csv column matching "First name" or "Prénom" will be assigned to the `first_name` attribute
  #   column :first_name, as: [/first ?name/i, /pr(é|e)nom/i]
  #
  #   # the csv column "first_name" will be assigned to the `f_name` attribute
  #   column :first_name, to: :f_name
  #
  #   # email will be downcased
  #   column :email, to: ->(email) { email.downcase }
  #
  #   # transform `confirmed` to `confirmed_at`
  #   column :confirmed, to: ->(confirmed, model) do
  #     model.confirmed_at = confirmed == "true" ? Time.new(2012) : nil
  #   end
  #
  class ColumnDefinition
    include Virtus.model

    attribute :name, Symbol
    attribute :to # Symbol or Proc
    attribute :as # Symbol, String, Regexp, Array
    attribute :required, Boolean

    # The model attribute that this column targets
    def attribute
      if to.is_a?(Symbol)
        to
      else
        name
      end
    end

    # Return true if column definition matches the column name passed in.
    def match?(column_name, search_query=(as || name))
      return false if column_name.nil?

      downcased_column_name = column_name.downcase
      underscored_column_name = downcased_column_name.gsub(/\s+/, '_')

      case search_query
      when Symbol
        underscored_column_name == search_query.to_s
      when String
        downcased_column_name == search_query.downcase
      when Regexp
        column_name =~ search_query
      when Array
        search_query.any? { |query| match?(column_name, query) }
      else
        raise Error, "Invalid `as`. Should be a Symbol, String, Regexp or Array - was #{as.inspect}"
      end
    end
  end

  # A Column from a CSV file with a `name` (from the csv file) and a matching
  # `ColumnDefinition` if any.
  class Column
    include Virtus.model

    attribute :name, String
    attribute :definition, ColumnDefinition
  end

  # The CSV Header
  class Header
    include Virtus.model

    attribute :column_definitions, Array[ColumnDefinition]
    attribute :column_names, Array[String]

    def columns
      column_names.map do |column_name|
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
      column_names - column_definition_names
    end

    # Returns Array[Symbol]
    def missing_required_columns
      required_columns - column_names.map { |name| find_column_definition(name) }.compact.map(&:name)
    end

    # Returns Array[Symbol]
    def missing_columns
      column_definition_names - column_names
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

  # A Row from the CSV file.
  #
  # Using the header, the model_klass and the identifier it builds the model
  # to be persisted.
  class Row
    include Virtus.model

    attribute :header, Header
    attribute :row_array, Array[String]
    attribute :model_klass
    attribute :identifier

    # The model to be persisted
    def model
      @model ||= begin
        model = if identifier
          value = csv_attributes[header.column_name_for_model_attribute(identifier)]
          model_klass.public_send("find_by_#{identifier}", value)
        end

        model ||= model_klass.new
        set_attributes(model)
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
        column_definition = column.definition

        next if column_definition.nil?

        set_attribute(model, column_definition, value)
      end
    end

    # Set the attribute using the column_definition and the csv_value
    def set_attribute(model, column_definition, csv_value)
      if column_definition.to && column_definition.to.is_a?(Proc)
        to_proc = column_definition.to

        case to_proc.arity
        when 1 # to: ->(email) { email.downcase }
          model.public_send("#{column_definition.name}=", to_proc.call(csv_value))
        when 2 # to: ->(published, post) { post.published_at = Time.now if published == "true" }
          to_proc.call(csv_value, model)
        else
          raise ArgumentError, "`to` proc can only have 1 or 2 arguments"
        end
      else
        attribute = column_definition.attribute
        model.public_send("#{attribute}=", csv_value)
      end

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
  end

  # The Report you get back from an import.
  #
  # * It has a status (pending, invalid_csv_file, invalid_header, in_progress, done, aborted)
  # * It lists out missing columns
  # * It reports parser_error
  # * It lists out (created / updated) * (success / failed) records
  # * It provides a human readable message
  #
  class Report
    include Virtus.model

    attribute :status, Symbol, default: proc { :pending }

    attribute :missing_columns, Array[Symbol], default: proc { [] }

    attribute :parser_error, String

    attribute :created_rows, Array[Row], default: proc { [] }
    attribute :updated_rows, Array[Row], default: proc { [] }
    attribute :failed_to_create_rows, Array[Row], default: proc { [] }
    attribute :failed_to_update_rows, Array[Row], default: proc { [] }

    attribute :message_generator, Class, default: proc { ReportMessage }

    def valid_rows
      created_rows + updated_rows
    end

    def invalid_rows
      failed_to_create_rows + failed_to_update_rows
    end

    def all_rows
      valid_rows + invalid_rows
    end

    def success?
      done? && invalid_rows.empty?
    end

    def pending?;     status == :pending;         end
    def in_progress?; status == :in_progress;     end
    def done?;        status == :done;            end
    def aborted?;     status == :aborted;         end
    def invalid_header?; status == :invalid_header; end
    def invalid_csv_file?; status == :invalid_csv_file; end

    def pending!;     self.status = :pending;     self; end
    def in_progress!; self.status = :in_progress; self; end
    def done!;        self.status = :done;        self; end
    def aborted!;     self.status = :aborted;     self; end
    def invalid_header!; self.status = :invalid_header; self; end
    def invalid_csv_file!; self.status = :invalid_csv_file; self; end

    def message
      message_generator.call(self)
    end
  end

  class ReportMessage
    def self.call(report)
      new(report).to_s
    end

    def initialize(report)
      @report = report
    end

    attr_accessor :report

    def to_s
      send("report_#{report.status}")
    end

    private

    def report_pending
      "Import hasn't started yet"
    end

    def report_in_progress
      "Import in progress"
    end

    def report_done
      "Import completed: " + import_details
    end

    def report_invalid_header
      "The following columns are required: #{report.missing_columns.join(", ")}"
    end

    def report_invalid_csv_file
      report.parser_error
    end

    def report_aborted
      "Import aborted"
    end

    # Generate something like: "3 created. 4 updated. 1 failed to create. 2 failed to update."
    def import_details
      report.attributes
        .select { |name, _| name["_rows"] }
        .select { |_, instances| instances.size > 0 }
        .map { |bucket, instances| "#{instances.size} #{bucket.to_s.gsub('_rows', '').gsub('_', ' ')}" }
        .join(", ")
    end

  end

  # Do the actual import.
  #
  # It iterates over the rows' models and persist them. It returns a `Report`.
  class Runner
    def self.call(*args)
      new(*args).call
    end

    include Virtus.model

    attribute :rows, Array[Row]
    attribute :when_invalid, Symbol

    attribute :report, Report, default: proc { Report.new }

    ImportAborted = Class.new(StandardError)

    # Persist the rows' model and return a `Report`
    def call
      if rows.empty?
        report.done!
        return report
      end

      report.in_progress!

      rows.first.model.class.transaction do
        rows.each do |row|
          if row.model.persisted?
            if row.model.save
              report.updated_rows << row
            else
              report.failed_to_update_rows << row
              raise ImportAborted if abort_when_invalid?
            end
          else
            if row.model.save
              report.created_rows << row
            else
              report.failed_to_create_rows << row
              raise ImportAborted if abort_when_invalid?
            end
          end
        end
      end

      report.done!
      report
    rescue ImportAborted
      report.aborted!
      report
    end

    private

    def abort_when_invalid?
      when_invalid == :abort
    end
  end

  # The configuration of a CSVImporter
  class Config
    include Virtus.model

    attribute :model
    attribute :column_definitions, Array[ColumnDefinition], default: proc { [] }
    attribute :identifier, Symbol
    attribute :when_invalid, Symbol, default: proc { :skip }
  end

  class Error < StandardError
  end

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
  end

  attr_reader :csv, :report, :config

  # Initialize and return the `Header` for the current CSV file
  def header
    @header ||= Header.new(column_definitions: config.column_definitions, column_names: csv.header)
  end

  # Initialize and return the `Row`s for the current CSV file
  def rows
    csv.rows.map { |row_array| Row.new(header: header, row_array: row_array,
                                       model_klass: config.model, identifier: config.identifier) }
  end

  # Run the import. Return a Report.
  def run!
    if header.valid?
      @report = Runner.call(rows: rows, when_invalid: config.when_invalid)
    else
      @report = Report.new(status: :invalid_header, missing_columns: header.missing_required_columns)
    end

  rescue CSV::MalformedCSVError => e
    @report = Report.new(status: :invalid_csv_file, parser_error: e.message)
  end

end

