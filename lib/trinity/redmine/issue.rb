module Trinity
  module Redmine
    class Issue < RestAPI

      def find_blocked_issue_ids(issue)



        issue = Trinity::Redmine::Issue.find(4257, :params => {:include => 'relations'})

        if !issue.respond_to? 'relations'
          nil
        else
          relations = issue.relations.select { |relation| (relation.issue_id != issue.id and relation.relation_type.to_s.eql? 'blocks') }
        end

        i = []
        relations.each do |relation|
          i << relation.issue_id
        end
      end

    end
  end
end
