module CSVImporter
  # Generate a human readable message for the given report.
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

  end # class ReportMessage
end
