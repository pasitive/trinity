module Trinity

  require 'active_resource'

  require 'trinity/redmine/rest_api'
  require 'trinity/redmine/issue'
  require 'trinity/redmine/version'

  ActiveResource::Base.logger = Logger.new(STDERR)

  class Redmine
    class << self

      def fetch_issues(params)
        p = {
            :limit => 999,
        }
        p = p.merge(params) if params.is_a?(Hash)

        Trinity::Issue.find(:all, :params => p)
      end

      def fetch_issues_by_filter_id(query_id, params)
        p = {
            :query_id => query_id,
        }
        p = p.merge(params) if params.is_a?(Hash)

        fetch_issues(p)
      end

      def create_version(project_name, name)
        version = Trinity::Version.create_version(project_name, name)
        version
      end
    end
  end
end