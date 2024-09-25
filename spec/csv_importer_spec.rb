require 'spec_helper'
require 'set'

# High level integration specs
describe CSVImporter do
  # Mimics an active record model
  class User
    include Virtus.model
    include ActiveModel::Model

    attribute :id
    attribute :email
    attribute :f_name
    attribute :l_name
    attribute :confirmed_at
    attribute :created_by_user_id
    attribute :custom_fields, Hash

    validates_presence_of :email
    validates_format_of :email, with: /[^@]+@[^@]/ # contains one @ symbol
    validates_presence_of :f_name

    def self.transaction
      yield
    end

    def persisted?
      !!id
    end

    def save
      return false unless valid?

      unless persisted?
        @id = rand(100)
        self.class.store << self
      end

      true
    end

    def self.find_by(attributes)
      store.find { |u| attributes.all? { |k, v| u.attributes[k] == v } }
    end

    def self.reset_store!
      @store = Set.new

      User.new(
        email: "mark@example.com", f_name: "mark", l_name: "lee", confirmed_at: Time.new(2012)
      ).save

      @store
    end

    def self.store
      @store ||= reset_store!
    end
  end

  class ImportUserCSV
    include CSVImporter

    class ConfirmedProcessor
      def self.call(confirmed, model)
        model.confirmed_at = confirmed == "true" ? Time.new(2012) : nil
      end
    end

    model User

    column :email, required: true, as: /email/i, to: ->(email) { email.downcase }
    column :f_name, as: :first_name, required: true
    column :last_name,  to: :l_name
    column :confirmed,  to: ConfirmedProcessor
    column :extra, as: /extra/i, to: ->(value, model, column) do
      model.custom_fields[column.name] = value
    end

    identifier :email # will find_or_update via

    when_invalid :skip # or :abort
  end

  class ImportUserCSVByFirstName
    include CSVImporter

    model User

    column :email, required: true
    column :first_name, to: :f_name, required: true
    column :last_name,  to: :l_name
    column :confirmed,  to: ->(confirmed, model) do
      model.confirmed_at = confirmed == "true" ? Time.new(2012) : nil
    end

    identifier :f_name

    when_invalid :abort

    after_build do |model|
      model.email.downcase! if model.email
    end
  end

  before do
    User.reset_store!
  end

  describe "happy path" do
    it 'imports' do
      csv_content = "email,confirmed,first_name,last_name,extra_1,extra_2
BOB@example.com,true,bob,,meta1,meta2"

      import = ImportUserCSV.new(content: csv_content)
      expect(import.rows.size).to eq(1)

      row = import.rows.first

      expect(row.csv_attributes).to eq(
        {
          "email" => "BOB@example.com",
          "first_name" => "bob",
          "last_name" => "",
          "confirmed" => "true",
          "extra_1" => "meta1",
          "extra_2" => "meta2",
        }
      )

      import.run!

      expect(import.report.valid_rows.size).to eq(1)
      expect(import.report.created_rows.size).to eq(1)

      expect(import.report.message).to eq "Import completed: 1 created"

      model = import.report.valid_rows.first.model
      expect(model).to be_persisted
      expect(model).to have_attributes(
        "email" => "bob@example.com", # was downcased!
        "f_name" => "bob",
        "l_name" => "",
        "confirmed_at" => Time.new(2012),
        "custom_fields" => {
          "extra_1" => "meta1",
          "extra_2" => "meta2"
        }
      )
    end

      it "records the correct line number for each row" do
        csv_content = "email,confirmed,first_name,last_name
BOB@example.com,true,bob,,"
        import = ImportUserCSV.new(content: csv_content)
        import.run!

        expect(import.report.valid_rows.size).to eq(1)
        expect(import.report.created_rows.size).to eq(1)
        expect(import.report.created_rows.first.line_number).to eq(2)
      end
  end

  describe "invalid records" do
    it "does not import them" do
      csv_content = "email,confirmed,first_name,last_name
  NOT_AN_EMAIL,true,bob,,"
      import = ImportUserCSV.new(content: csv_content)
      import.run!

      expect(import.rows.first.model).to_not be_persisted

      expect(import.report.valid_rows.size).to eq(0)
      expect(import.report.created_rows.size).to eq(0)
      expect(import.report.invalid_rows.size).to eq(1)
      expect(import.report.failed_to_create_rows.size).to eq(1)

      expect(import.report.message).to eq "Import completed: 1 failed to create"
    end

    it "maps errors back to the csv header column name" do
      csv_content = "email,confirmed,first_name,last_name
  bob@example.com,true,,last,"
      import = ImportUserCSV.new(content: csv_content)
      import.run!

      row = import.report.invalid_rows.first
      expect(row.errors.size).to eq(1)
      expect(row.errors).to eq("first_name" => "can't be blank")
    end

    it "records the correct line number for each row" do
      csv_content = "email,confirmed,first_name,last_name
  bob@example.com,true,,last,"
      import = ImportUserCSV.new(content: csv_content)
      import.run!

      expect(import.report.invalid_rows.first.line_number).to eq(2)
      expect(import.report.failed_to_create_rows.first.line_number).to eq(2)
    end
  end

  describe "missing required columns" do
    let(:csv_content) do
"confirmed,first_name,last_name
bob@example.com,true,,last,"
    end

    let(:import) { ImportUserCSV.new(content: csv_content) }

    it "lists missing required columns" do
      expect(import.header.missing_required_columns).to eq(["email"])
    end

    it "is not a valid header" do
      expect(import.header).to_not be_valid
    end

    it "returns a report when you attempt to run the report" do
      import.valid_header?
      report = import.report

      expect(import.run!).to eq(report)

      expect(report).to_not be_success
      expect(report.status).to eq(:invalid_header)
      expect(report.missing_columns).to eq(["email"])
      expect(report.message).to eq("The following columns are required: email")
    end
  end

  describe "missing columns" do
    it "lists missing columns" do
      csv_content = "email,first_name,
  bob@example.com,bob,"
      import = ImportUserCSV.new(content: csv_content)

      expect(import.header.missing_required_columns).to be_empty
      expect(import.header.missing_columns)
        .to eq(["last_name", "confirmed", "extra"])
    end
  end

  describe "extra columns" do
    it "lists extra columns" do
      csv_content = "email,confirmed,first_name,last_name,age
  bob@example.com,true,,last,"
      import = ImportUserCSV.new(content: csv_content)

      expect(import.header.extra_columns).to eq(["age"])

      report = import.run!
      expect(report.extra_columns).to eq(["age"])
    end
  end

  describe "find or create" do
    it "finds or create via identifier" do
      csv_content = "email,confirmed,first_name,last_name
bob@example.com,true,bob,,
mark@example.com,false,mark,new_last_name"
      import = ImportUserCSV.new(content: csv_content)

      import.run!

      expect(import.report.valid_rows.size).to eq(2)
      expect(import.report.created_rows.size).to eq(1)
      expect(import.report.updated_rows.size).to eq(1)

      model = import.report.created_rows.first.model
      expect(model).to be_persisted
      expect(model).to have_attributes(
        email: "bob@example.com",
        f_name: "bob",
        l_name: "",
        confirmed_at: Time.new(2012)
      )

      model = import.report.updated_rows.first.model
      expect(model).to be_persisted
      expect(model).to have_attributes(
        email: "mark@example.com",
        f_name: "mark",
        l_name: "new_last_name",
        confirmed_at: nil
      )

      expect(import.report.message).to eq "Import completed: 1 created, 1 updated"
    end

    it "finds or create by identifier when the attributes does not match the column header" do
      csv_content = "email,confirmed,first_name,last_name
mark-new@example.com,false,mark,new_last_name"
      import = ImportUserCSVByFirstName.new(content: csv_content)

      import.run!

      expect(import.report.updated_rows.size).to eq(1)

      model = import.report.updated_rows.first.model
      expect(model).to be_valid
      expect(model).to have_attributes(
        email: "mark-new@example.com",
        f_name: "mark",
        l_name: "new_last_name",
        confirmed_at: nil
      )
    end

    it "applies transformation before running the find" do
      csv_content = "email,confirmed,first_name,last_name
MARK@EXAMPLE.COM,false,mark,new_last_name"

      import = ImportUserCSV.new(content: csv_content)

      import.run!

      expect(import.report.created_rows.size).to eq(0)
      expect(import.report.updated_rows.size).to eq(1)

      model = import.report.updated_rows.first.model
      expect(model).to be_valid
      expect(model).to have_attributes(
        email: "mark@example.com",
        f_name: "mark",
        l_name: "new_last_name",
        confirmed_at: nil
      )
    end

    it "allows for missing identifiers" do
      csv_content = "email,confirmed,first_name,last_name
mark-new@example.com,false,mark,new_last_name"
      import = ImportUserCSVByFirstName.new(content: csv_content) do
        identifier :id
      end

      import.run!

      expect(import.report.created_rows.size).to eq(1)
    end

    it "handles errors just fine" do
      csv_content = "email,confirmed,first_name,last_name
mark@example.com,false,,new_last_name"
      import = ImportUserCSV.new(content: csv_content)

      import.run!

      expect(import.report.valid_rows.size).to eq(0)
      expect(import.report.created_rows.size).to eq(0)
      expect(import.report.updated_rows.size).to eq(0)
      expect(import.report.failed_to_create_rows.size).to eq(0)
      expect(import.report.failed_to_update_rows.size).to eq(1)
      expect(import.report.message).to eq "Import completed: 1 failed to update"

      model = import.report.failed_to_update_rows.first.model
      expect(model).to be_persisted
      expect(model).to have_attributes(
        email: "mark@example.com",
        f_name: "",
        l_name: "new_last_name",
        confirmed_at: nil
      )
    end

    it "handles multiple identifiers" do
      csv_content = "email,confirmed,first_name,last_name
updated-mark@example.com,false,mark,lee
new-mark@example.com,false,mark,moo"
      import = ImportUserCSV.new(content: csv_content) do
        identifiers :f_name, :l_name
      end

      import.run!

      expect(import.report.message).to eq "Import completed: 1 created, 1 updated"
    end

    it "handles proc identifiers" do
      csv_content = "email,confirmed,first_name,last_name
mark@example.com,false,mark,lee
mark@example.com,false,mark,
updated-mark@example.com,false,mark,moo"
      import = ImportUserCSV.new(content: csv_content) do
        identifiers ->(user) { user.l_name.empty? ? :email : %i[f_name l_name] }
      end

      import.run!

      expect(import.report.message).to eq "Import completed: 1 created, 2 updated"
    end
  end # describe "find or create"

  it "strips cells" do
    csv_content = "email,confirmed,first_name,last_name
bob@example.com   ,  true,   bob   ,,"
    import = ImportUserCSV.new(content: csv_content)

    import.run!

    model = import.report.created_rows.first.model
    expect(model).to have_attributes(
      email: "bob@example.com",
      confirmed_at: Time.new(2012),
      f_name: "bob",
      l_name: ""
    )
  end

  it "strips and downcases columns" do
    csv_content = "Email,Confirmed,First name,last_name
bob@example.com   ,  true,   bob   ,,"
    import = ImportUserCSV.new(content: csv_content)

    expect { import.run! }.to_not raise_error
  end

  it "imports from a file (IOStream)" do
    csv_content = "Email,Confirmed,First name,last_name
bob@example.com   ,  true,   bob   ,,"
    csv_io = StringIO.new(csv_content)
    import = ImportUserCSV.new(file: csv_io)

    expect { import.run! }.to_not raise_error
  end

  it "supports invisible characters" do
    csv_content = "Email,Confirmed,First name,last_name
bob@example.com   ,  true,   bob   ,,"

    # insert invisible characters
    csv_content.insert(-1, "\u{FEFF}")

    csv_io = StringIO.new(csv_content)
    import = ImportUserCSV.new(file: csv_io)

    expect { import.run! }.to_not raise_error
  end

  it "imports from a path" do
    import = ImportUserCSV.new(path: "spec/fixtures/valid_csv.csv")

    expect { import.run! }.to_not raise_error
  end

  it "supports custom quote_char value" do
    csv_content = "email,confirmed,first_name,last_name
bob@example.com   ,  true,   bob   , \"the dude\" jones,"
    import = ImportUserCSV.new(content: csv_content, quote_char: "\x00")

    import.run!

    model = import.report.created_rows.first.model
    expect(model).to have_attributes(
      email: "bob@example.com",
      confirmed_at: Time.new(2012),
      f_name: "bob",
      l_name: "\"the dude\" jones"
    )
  end

  it "converts empty cells to an empty string" do
    csv_content = "email,confirmed,first_name,last_name
,,,,"
    import = ImportUserCSV.new(content: csv_content)

    expect {
      import.run!
    }.to_not raise_error(NoMethodError, "undefined method `downcase' for nil:NilClass")
  end

  it "sets default attributes" do
    csv_content = "Email,Confirmed,First name,last_name
  bob@example.com   ,  true,   bob   ,,"
    default_values = {created_by_user_id: 123}
    import = ImportUserCSV.new(content: csv_content, default_values: default_values)

    import.run!

    model = import.report.created_rows.first.model
    expect(model).to have_attributes({created_by_user_id: 123})
  end

  describe "#when_invalid" do
    it "could abort" do
      csv_content = "email,confirmed,first_name,last_name
bob@example.com,true,,
mark@example.com,false,mark," # missing first names

      import = ImportUserCSVByFirstName.new(content: csv_content)

      expect { import.run! }.to_not raise_error

      expect(import.report.valid_rows.size).to eq(0)
      expect(import.report.created_rows.size).to eq(0)
      expect(import.report.updated_rows.size).to eq(0)
      expect(import.report.failed_to_create_rows.size).to eq(1)
      expect(import.report.failed_to_update_rows.size).to eq(0)

      expect(import.report.message).to eq "Import aborted"
    end
  end

  describe "updating config on the fly" do
    it "works" do
      csv_content = "email,confirmed,first_name,last_name
new-mark@example.com,false,new mark,lee"

      import = ImportUserCSV.new(content: csv_content) do
        identifiers :l_name
      end

      report = import.run!

      expect(report.created_rows.size).to eq(0)
      expect(report.updated_rows.size).to eq(1)

    end
  end

  it "handles invalid csv files" do
    csv_content = %|email,confirmed,first_name,last_name,,
bob@example.com,"false"
bob@example.com,false,,in,,,"""|

    expect(ImportUserCSV.new(content: csv_content)).to_not be_valid_header

    import = ImportUserCSV.new(content: csv_content).run!

    expect(import).to_not be_success
    expect(import.message).to include "Unclosed quoted field"
  end

  it "matches columns via regexp" do
    csv_content = %|Email Address,confirmed,first_name,last_name,,
bob@example.com,false,bob,,|

    import = ImportUserCSV.new(content: csv_content).run!

    expect(import).to be_success
    expect(import.message).to eq "Import completed: 1 created"
  end

  describe ".after_build" do

    it "overwrites attributes" do
      csv_content = "email,confirmed,first_name,last_name
BOB@example.com,true,bob,,"

      # This importer downcases emails after build
      ImportUserCSVByFirstName.new(content: csv_content).run!

      expect(User.store.map(&:email)).to include "bob@example.com"
    end

    it "overwrites attributes at runtime" do
      csv_content = "email,confirmed,first_name,last_name
  bob@example.com,true,bob,,"
      current_user_id = 3

      import = ImportUserCSV.new(content: csv_content) do
        after_build do |model|
          model.created_by_user_id = current_user_id
        end
      end

      import.run!

      model = User.find_by(email: "bob@example.com")

      expect(model.created_by_user_id).to eq(current_user_id)
    end

    it "supports multiple blocks to be ran" do
      csv_content = "email,confirmed,first_name,last_name
  BOB@example.com,true,bob,,"
      current_user_id = 3

      import = ImportUserCSVByFirstName.new(content: csv_content) do
        after_build do |model|
          model.created_by_user_id = current_user_id
        end

        after_build do |model|
          model.email.gsub!('@', '+imported@') if model.email
        end
      end

      import.run!

      expect(User.store.map(&:email)).to include "bob+imported@example.com"

      model = User.find_by(email: "bob+imported@example.com")
      expect(model.created_by_user_id).to eq(current_user_id)
    end

    it "does not leak between two overwrittes" do
      csv_content = "email,confirmed,first_name,last_name
  bob@example.com,true,bob,,"
      log = []

      import_foo = ImportUserCSV.new(content: csv_content) do
        after_build do |model|
          log << "foo"
        end
      end

      import_bar = ImportUserCSV.new(content: csv_content) do
        after_build do |model|
          log << "bar"
        end
      end

      import_foo.run!

      expect(log).to eq ["foo"]
    end
  end # describe ".after_build"

  describe ".after_save" do
    it "is triggered after each save and supports multiple blocks" do
      csv_content = "email,first_name,last_name
                     bob@example.com,bob,,
                     invalid,bob,,"

      success_array = []
      saves_count = 0

      import = ImportUserCSV.new(content: csv_content) do
        after_save do |user|
          success_array << user.persisted?
        end

        after_save do
          saves_count += 1
        end

        after_save do |user, attributes|
          # representing maybe a realistic OtherResource.find_by(name: 'invalid')
          if user.email == 'invalid'
            user.errors.add(:email, "'#{ attributes['email'] }' could not be found")
          end
        end
      end

      expect {
        import.run!
      }.to change { success_array }.from([]).to([true, false])

      expect(saves_count).to eq 2

      failed_row = import.report.failed_to_create_rows.first
      expect(failed_row.model.errors[:email]).to include("'invalid' could not be found")
    end
  end

  describe "skipping" do
    it "could skip via throw :skip" do
      csv_content = "email,confirmed,first_name,last_name
bob@example.com,true,bob,,
mark@example.com,false,mark,new_last_name"
      import = ImportUserCSV.new(content: csv_content) do
        after_build do |user|
          skip! if user.persisted?
        end
      end

      import.run!
      expect(import.report.message).to eq "Import completed: 1 created, 1 update skipped"
    end

    it "doesn't call skip! twice" do
      csv_content = "email,confirmed,first_name,last_name
bob@example.com,true,bob,,
mark@example.com,false,mark,new_last_name"
      import = ImportUserCSV.new(content: csv_content) do
        after_build do |user|
          skip! unless user.persisted?
        end
      end

      import.run!
      expect(import.report.message).to eq "Import completed: 1 updated, 1 create skipped"
    end
  end # describe "skipping"
end
