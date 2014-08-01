# encoding: utf-8

module Trinity
  module Transitions
    class TmpReport < Transition

      def initialize
        super
      end

      def check(issue, params)
        valid = true



        valid
      end

      def handle(issue)

        current = Trinity::Redmine::Issue.find(issue.id, :params => {:include => 'changesets,journals'})

        found = false

        last_user_id = Trinity::Redmine::Issue.get_last_user_id_from_changesets(current)
        issue.assigned_to_id = last_user_id
        found = true if !last_user_id.nil?

        if !found
          users = Trinity::Redmine::Issue.filter_users_from_journals_by_group_id(current, @group_users)
          last_user_id = users.sample if users.size > 0
          issue.assigned_to_id = last_user_id
          found = true if !last_user_id.nil?
        end

        if !found
          puts "Мне не удалось найти сотрудника не по коммитам, не по журналу.\nВам необходимо вручную найти в истории нужного сотрудника и переназначить задачу на него."
        end

      end

    end
  end
end