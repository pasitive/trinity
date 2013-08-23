module Trinity
  module Config

    # Configuration default values
    @defaults = {
        'email_delivery' => nil,
    }

    @config = nil

    class << self

      # Loads the Trinity configuration file
      # Valid options:
      # * :file: the configuration file to load (default: config.yaml)
      def load(options={})

        filename = options[:file] || File.join('config.yaml')

        @config = @defaults.dup

        if File.file?(filename)
          @config.merge!(load_from_yaml(filename))
        end

        if @config['email_delivery']
          @config['email_delivery'].each do |k, v|
            v.symbolize_keys! if v.respond_to?(:symbolize_keys!)
          end
          c = @config['email_delivery']
          Mail.defaults do
            delivery_method c['delivery_method'], c['smtp_settings']
          end
        end

        @config
      end

      # Returns a configuration setting
      def [](name)
        load unless @config
        @config[name]
      end

      private

      def load_from_yaml(filename)
        yaml = nil
        begin
          yaml = YAML::load(File.read(filename))
        rescue ArgumentError
          $stderr.puts "Your Trinity configuration file located at #{filename} is not a valid YAML file and could not be loaded."
          exit 1
        end
        conf = {}
        if yaml.is_a?(Hash)
          if yaml['default']
            conf.merge!(yaml['default'])
          end
        else
          $stderr.puts "Your Trinity configuration file located at #{filename} is not a valid Trinity configuration file."
          exit 1
        end
        conf
      end

    end
  end
end
