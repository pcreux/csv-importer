module CSVImporter
  class Railtie < ::Rails::Railtie
    config.to_prepare do
      I18n.load_path.concat(Dir.glob(File.join(File.dirname(__FILE__), 'locales/*.yml')))
    end
  end
end
