module Trinity

  require 'active_resource'

  ActiveResource::Base.logger = Logger.new(STDERR)

  class RestAPI < ActiveResource::Base
    self.site = 'http://r.itcreativoff.com'
    self.user = 'trinity'
    self.password = 'trinity'
    self.format = :xml
  end

  class Issue < RestAPI
  end

  class Version < RestAPI
    class << self
      def create_version(project_name, name)

        params = {
            :project_id => project_name,
            :name => name
        }

        version = Trinity::Version.new(params)
        need_save = true

        self.prefix = '/projects/' + project_name + '/'
        Trinity::Version.find(:all, :params => {:status => 'open'}).each do |v|
          if v.name.eql? name
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


  class Redmine
    class << self

      def fetch_issues_by_filter_id(query_id, params)


        p = {
            :query_id => query_id,
            :limit => 999,
        }

        p = p.merge(params) if params.is_a?(Hash)

        Trinity::Issue.find(:all, :params => p)
      end

      def create_version(project_name, name)
        version = Trinity::Version.create_version(project_name, name)
        version
      end

      def assign_resolved_issues_to_author(query_id)


      end

    end

  end
end