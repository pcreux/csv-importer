module CSVImporter
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
end
