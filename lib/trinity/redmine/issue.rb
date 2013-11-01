module Trinity
  module Redmine
    class Issue < RestAPI

      def cf(id, value = nil)
        if self.respond_to? 'custom_fields'
          cf = self.custom_fields.select { |i| i.id.to_i.eql? id }.first
          cf.value = value.to_s if !value.nil?
          cf
        else
          logmsg :warn, "Issue #{self.id} have no custom field with id=#{id}"
          nil
        end
      end

      def self.find_related_blocked_ids(issue_id)
        issue = Trinity::Redmine::Issue.find(issue_id, :params => {:include => 'relations'})
        if issue.respond_to? 'relations'
          relations = issue.relations.select { |relation| (relation.issue_id != issue.id and relation.relation_type.to_s.eql? 'blocks') }
          issue_ids = []
          relations.each do |relation|
            issue_ids << relation.issue_id
          end
          issue_ids
        else
          nil
        end
      end

      class << self

        def get_last_user_id_from_changesets(issue)
          issue.changesets.last.user.id
        rescue NoMethodError => e
          logmsg :warn, "No commits assigned to issue ##{issue.id} (#{e.message})"
        rescue StandardError => e
          logmsg :error, e.message + e.backtrace.inspect
        end

        def filter_users_from_journals_by_group_id(issue, group_users)
          begin
            users = issue.journals.inject([]) do |result, journal|
              result << journal.user.id.to_i if (group_users.include? journal.user.id.to_i)
              result
            end

            users.uniq!

          rescue NoMethodError
            logmsg :warn, "No journals assigned to issue ##{issue.id} (#{e.message})"
          rescue StandardError
            logmsg :error, e.message + e.backtrace.inspect
          end
        end


      end

    end
  end
end
