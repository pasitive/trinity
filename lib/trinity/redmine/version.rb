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

          version = self.find_version(project_name, name, 'open')

          if version.nil?
            version = self.new(params)
            version.due_date = date.strftime('%Y-%m-%d')
            version.save
          end

          version
        end

        def find_version(project_name, branch, status = 'open')
          versions = self.fetch_versions(project_name, status)
          version = nil
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