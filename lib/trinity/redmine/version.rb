module Trinity
  module Redmine
    class Version < RestAPI
      class << self

        def create_version(project_name, name)

          params = {
              :project_id => project_name,
              :name => name
          }

          begin
            date = Date.parse(name.split('_').drop(1).join('-'))
          rescue ArgumentError => e
            throw e
          end
          version = Trinity::Redmine::Version.new(params)
          version.due_date = date.strftime('%Y-%m-%d')
          need_save = true

          self.prefix = '/projects/' + project_name + '/'
          self.find(:all).each do |v|
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

        def find_version(project_name, branch, status = 'open')
          versions = self.fetch_versions(project_name, status)
          version = nil
          self.prefix = '/projects/' + project_name + '/'
          versions.each do |v|
            v.name.strip!
            v.status.strip!
            if v.name.eql? branch and v.status.eql? status
              version = v
              break
            end
          end
          version
        end

        def fetch_versions(project_name, status = 'open')
          versions = []
          self.prefix = '/projects/' + project_name + '/'
          self.find(:all).each do |v|
            next if v.status.eql? 'closed'
            v.name.strip!
            v.status.strip!
            if v.status.eql? status
              versions << v
            end
          end
          versions
        end

      end
    end
  end
end