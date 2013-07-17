module Trinity
  class Version < RestAPI
    class << self

      def create_version(project_name, name)

        params = {
            :project_id => project_name,
            :name => name
        }

        date = Date.parse(name.split('_').drop(1).join('-'))
        version = Trinity::Version.new(params)
        version.due_date = date.strftime('%Y-%m-%d')
        need_save = true

        self.prefix = '/projects/' + project_name + '/'
        Trinity::Version.find(:all).each do |v|
          if v.name.eql? name and v.status.eql? "open"
            need_save = false
            version = v
            puts "Found created version #{v.name}"
            break
          end
        end

        if need_save
          version.save
          puts "Created version #{version.id} #{version.name}"
        else
          puts "Loaded version #{version.id} #{version.name}"
        end

        version
      end

    end
  end
end