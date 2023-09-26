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
    attribute :sql_transaction, Symbol

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

    def sql_transaction_all_rows?
      sql_transaction == :all_rows
    end

    def sql_transaction_one_row?
      sql_transaction == :each_row
    end

    def persist_rows!
      full_transaction do
        rows.each do |row|
          transaction do
            tags = []

            if row.model.persisted?
              tags << :update
            else
              tags << :create
            end

            if row.skip?
              tags << :skip
            elsif row.errors.size > 0
              tags << :failure
            else
              if row.model.save
                tags << :success
              else
                tags << :failure
              end
            end

            add_to_report(row, tags)

            after_save_blocks.each do |block|
              case block.arity
              when 0 then block.call
              when 1 then block.call(row.model)
              when 2 then block.call(row.model, row.csv_attributes)
              else
                raise ArgumentError, "after_save block of arity #{ block.arity } is not supported"
              end
            end
          end
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
      when [ :create, :skip ]
        report.create_skipped_rows
      when [ :update, :skip ]
        report.update_skipped_rows
      else
        raise "Invalid tags #{tags.inspect}"
      end

      bucket << row

      raise ImportAborted if abort_when_invalid? && tags[1] == :failure
    end

    def full_transaction(&block)
      if sql_transaction_all_rows?
        rows.first.model.class.transaction(&block)
      else
        block.call
      end
    end

    def transaction(&block)
      if sql_transaction_one_row?
        rows.first.model.class.transaction(&block)
      else
        block.call
      end
    end
  end
end
