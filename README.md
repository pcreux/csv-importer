# CSVImporter

Importing a CSV file is easy to code until real users attempt to import
real data.

CSVImporter aims to handle validations, column mapping, actual import
and reporting.

[![Build
Status](https://travis-ci.org/BrewhouseTeam/csv-importer.svg)](https://travis-ci.org/BrewhouseTeam/csv-importer)
[![Code
Climate](https://codeclimate.com/github/BrewhouseTeam/csv-importer/badges/gpa.svg)](https://codeclimate.com/github/BrewhouseTeam/csv-importer)
[![Test
Coverage](https://codeclimate.com/github/BrewhouseTeam/csv-importer/badges/coverage.svg)](https://codeclimate.com/github/BrewhouseTeam/csv-importer/coverage)

## Usage

**This is still a work in progress**

Define your CSVImporter:

```ruby
class ImportUserCSV
  include CSVImporter

  model User

  column :email, to: ->(email) { email.downcase }, required: true
  column :first_name, as: [ /first.?name/i, /pr(é|e)nom/i ]
  column :last_name,  to: :l_name
  column :published,  to: ->(published, model) { model.published_at = published ? Time.now : nil }

  identifier :email # will find_or_update via :email

  when_invalid :skip # or :abort
end
```

Let's run an new import:

```ruby
# Import a file (IOStream or file path) and from CSV content

import = ImportUserCSV.new(file: InputStream)
import = ImportUserCSV.new(path: String)
import = ImportUserCSV.new(content: String)

# Validate header

import.header.valid?
  # => true if header is valid

import.header
  # => returns an instance of `CSVImporter::Header`

import.header.missing_required_columns # => ["email"]
import.header.missing_columns          # => ["email", "first_name"]
import.header.extra_columns            # => ["zip_code"]
import.header.columns                  # => ["last_name", "zip_code"]

# Manipulate rows

import.rows
  # => return a (lazy?) Array of Rows
row = rows.first

row.raw_string       # => "bob@example.com,bob,,extra"
row.raw_array        # => [ "bob@example.com", "bob", "", "extra" ]
row.csv_attributes   # => { email: "bob@example.com", first_name: "bob" }
row.model            # => User<email: "bob@example.com", f_name: "bob", id: nil>
row.valid?           # delegate to model.valid?

# Time to run the import!

report = import.run!

# The following methods return arrays of `Row`
report.valid_rows
report.invalid_rows
report.created_rows
report.updated_rows
report.failed_to_create_rows
report.failed_to_update_rows

report.success? # => true
report.message # => "Import completed. 4 created, 2 updated, 1 failed to update"
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'csv-importer'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install csv-importer

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release` to create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

1. Fork it ( https://github.com/BrewhouseTeam/csv-importer/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
