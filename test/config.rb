require 'yaml'

class TestConfig < Hash
  CONFIG_FILE = 'config.yml'

  def self.options
    @options ||= begin
      config_path = File.expand_path(CONFIG_FILE, File.dirname(__FILE__))

      unless (File.exist?(config_path))
        raise "Config #{CONFIG_FILE} not found. Copy test/config.example.yml and fill in appropriate test settings."
      end

      new(config_path)
    end
  end

  def initialize(path)
    merge!(symbolized_keys(YAML.load(File.open(path))))
  end

  def symbolized_keys(object)
    case (object)
    when Hash
      Hash[
        object.collect do |key, value|
          [
            key ? key.to_sym : key,
            symbolized_keys(value)
          ]
        end
      ]
    when Array
      object.collect do |value|
        symbolized_keys(value)
      end
    else
      object
    end
  end
end
