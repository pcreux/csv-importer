require "simplecov"
SimpleCov.start

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'active_model'

require 'csv_importer'

I18n.load_path << Dir[File.expand_path("lib/csv_importer/locales") + "/*.yml"]

RSpec.configure do |c|
  c.example_status_persistence_file_path = "./spec/examples.txt"
end
