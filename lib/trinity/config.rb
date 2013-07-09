module Trinity
  class Config

    def initialize
      $opts[:config] ||= 'config.yaml'
      raise('Config not found') unless File.exists? $opts[:config]
      @config = YAML.load(File.open($opts[:config]))
    end

    @@instance = Trinity::Config.new

    def self.instance
      return @@instance
    end

    def projects
      @config['projects']
    end

    def global(key)
      @config['global'][key]
    end

    private_class_method :new
  end
end