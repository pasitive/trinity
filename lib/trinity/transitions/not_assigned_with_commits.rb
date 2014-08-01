# encoding: utf-8

module Trinity
  module Transitions
    class NotAssignedWithCommits < Transition

      def initialize
        super
      end

      def check(issue, params)
        valid = true
        valid
      end

      def handle(issue)

        current = Trinity::Redmine::Issue.find(issue.id, :params => {:include => 'changesets,journals'})

        last_user_id = Trinity::Redmine::Issue.get_last_user_id_from_changesets(current)

        if !last_user_id.nil?
          issue.notes = "Установлен статус В работе, т.к. к задаче были прикреплены коммиты."
          issue.status_id = self.config['redmine']['status']['in_progress'].to_i
          issue.save
        end

        issue
      end

    end
  end
end