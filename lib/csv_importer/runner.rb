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
    attribute :after_save_blocks, Array[Proc], default: []

    attribute :report, Report, default: proc { Report.new }

    ImportAborted = Class.new(StandardError)

    # Persist the rows' model and return a `Report`
    def call
      if rows.empty?
        report.done!
        return report
      end

      report.in_progress!

      persist_rows!

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

    def persist_rows!
      transaction do
        rows.each do |row|
          tags = []

          if row.model.persisted?
            tags << :update
          else
            tags << :create
          end

          if row.model.save
            tags << :success
          else
            tags << :failure
          end

          add_to_report(row, tags)
          after_save_blocks.each { |block| block.call(row.model) }
        end
      end
    end

    def add_to_report(row, tags)
      bucket = case tags
      when [ :create, :success ]
        report.created_rows
      when [ :create, :failure ]
        report.failed_to_create_rows
      when [ :update, :success ]
        report.updated_rows
      when [ :update, :failure ]
        report.failed_to_update_rows
      else
        raise "Invalid tags #{tags.inspect}"
      end

      bucket << row

      raise ImportAborted if abort_when_invalid? && tags[1] == :failure
    end

    def transaction(&block)
      rows.first.model.class.transaction(&block)
    end
  end
end
