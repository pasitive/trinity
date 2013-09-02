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

        if @config['redmine']['connection']
          ActiveResource::Base.site = @config['redmine']['connection']['site']
          ActiveResource::Base.user = @config['redmine']['connection']['user']
          ActiveResource::Base.password = @config['redmine']['connection']['password']
          ActiveResource::Base.format = @config['redmine']['connection']['format'].to_sym
        end

        Trinity::Contacts::Jabber.defaults do |d|
          d.host = @config['notification']['jabber']['host']
          d.port = @config['notification']['jabber']['port']
          d.from_jid = @config['notification']['jabber']['from_jid']
          d.password = @config['notification']['jabber']['password']
        end

        # TODO consolidate this shit

        if @config['notification']['groups']['qa'] and @config['notification']['groups']['qa'].respond_to? 'each'
          @config['notification']['groups']['qa'].each do |buf|
            to_jid = buf.split('/')[0]
            name = buf.split('/')[1]

            Trinity.contact(:jabber) do |c|
              c.name = name
              c.group = 'qa'
              c.to_jid = to_jid
            end
          end
        end

        if @config['notification']['groups']['devel'] and @config['notification']['groups']['devel'].respond_to? 'each'
          @config['notification']['groups']['devel'].each do |buf|
            to_jid = buf.split('/')[0]
            name = buf.split('/')[1]

            Trinity.contact(:jabber) do |c|
              c.name = name
              c.group = 'devel'
              c.to_jid = to_jid
            end
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
