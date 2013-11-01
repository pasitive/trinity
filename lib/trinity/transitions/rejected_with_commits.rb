# encoding: utf-8

# Отклоненные задачи. Пытаемся найти разработчика по коммитам.

module Trinity
  module Transitions
    class RejectedWithCommits < Transition

      def initialize
        super
      end

      def check(issue, params)
        valid = true

        if !issue.respond_to? 'assigned_to'
          valid = false
        end

        if params['reject_to_group_id'].nil?
          logmsg :warn, 'reject_to_group_id parameter is not set'
        end

        @group_users = Trinity::Redmine::Groups.get_group_users(params['reject_to_group_id'])

        if valid && @group_users.include?(issue.assigned_to.id.to_i)
          logmsg(:info, "No action needed. Assigned to user is a member of #{@group.name} group")
          valid = false
        end

        valid
      end

      def handle(issue)

        current = Trinity::Redmine::Issue.find(issue.id, :params => {:include => 'changesets,journals'})

        if current.respond_to?(:changesets)
          last_user_id = Trinity::Redmine::Issue.get_last_user_id_from_changesets(issue)
          self.notes = "Переназначено на сотрудника, который вносил изменения последним."
          current.assigned_to_id = last_user_id
        elsif current.respond_to?(:journals)
          users = Trinity::Redmine::Issue.filter_users_from_journals_by_group_id(issue, @group_users)
          current.assigned_to_id = users.sample if users.size > 0
        else
          self.notes = "Мне не удалось найти сотрудника не по коммитам, не по журналу.\nВам необходимо вручную найти в истории нужного сотрудника и переназначить задачу на него."
        end

        if !self.config['redmine']['custom_fields']['returns'].nil?
          returns_id = self.config['redmine']['custom_fields']['returns'].to_i
          returns = issue.cf(returns_id)
          returns.value = (returns.value.to_i + 1).to_s
        end

        issue.priority_id = self.config['redmine']['priority']['critical'].to_i
        issue.notes = self.notes
        issue.save

        issue
      end

    end
  end
end