require 'spec_helper'

describe CSVImporter do
  it 'has a version number' do
    expect(CSVImporter::VERSION).not_to be nil
  end

  class User
    include Virtus.model
    include ActiveModel::Model

    attribute :email
    attribute :f_name
    attribute :l_name
    attribute :confirmed_at

    validates_presence_of :email
    validates_format_of :email, with: /[^@]+@[^@]/ # contains one @ symbol

    def valid?
      email
    end

    def persisted?
      @persisted ||= false
    end

    def save
      @persisted = true
    end
  end

  class ImportUserCSV
    include CSVImporter

    model User

    column :email
    column :first_name, to: :f_name
    column :last_name,  to: :l_name
    column :confirmed,  to: ->(confirmed, model) { model.confirmed_at = Time.new(2012) if confirmed == "true" }

    identifier :email # will find_or_update via

    when_invalid :skip # or :abort
  end

  describe "happy path" do
    it 'imports' do
      csv_content = "email,confirmed,first_name,last_name
bob@example.com,true,bob,,"

      import = ImportUserCSV.new(content: csv_content)
      expect(import.rows.size).to eq(1)

      row = import.rows.first

      expect(row.csv_attributes).to eq(
        {
          email: "bob@example.com",
          first_name: "bob",
          last_name: nil,
          confirmed: "true"
        }
      )

      import.run!

      expect(import.report.valid_rows.size).to eq(1)
      expect(import.report.created_rows.size).to eq(1)

      model = import.report.valid_rows.first.model
      expect(model).to be_persisted
      expect(model).to have_attributes(
        email: "bob@example.com",
        f_name: "bob",
        l_name: nil,
        confirmed_at: Time.new(2012)
      )
    end
  end

end
