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
      I18n.t('csv_importer.report_pending')
    end

    def report_in_progress
      I18n.t('csv_importer.report_in_progress')
    end

    def report_done
      I18n.t('csv_importer.report_done') + import_details
    end

    def report_invalid_header
      I18n.t('csv_importer.report_invalid_header') + ' ' +
      report.missing_columns.map {|c| I18n.t("csv_importer.#{c}") }.join(", ")
    end

    def report_invalid_csv_file
      report.parser_error
    end

    def report_aborted
      I18n.t('csv_importer.report_aborted')
    end

    # Generate something like: "3 created. 4 updated. 1 failed to create. 2 failed to update."
    def import_details
      report.attributes
        .select { |name, _| name["_rows"] }
        .select { |_, instances| instances.size > 0 }
        .map { |bucket, instances| I18n.t("csv_importer.#{bucket.to_s}", count: instances.size) }
        .join(", ")
    end

  end # class ReportMessage
end
