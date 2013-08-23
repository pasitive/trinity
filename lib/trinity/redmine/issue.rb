module Trinity
  module Redmine
    class Issue < RestAPI

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

    end
  end
end
