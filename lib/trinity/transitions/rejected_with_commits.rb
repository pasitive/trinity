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
          logmsg :warn, 'Issue is not assigned to anybody. assigned_to is null'
          valid = false
        end

        if params['reject_to_group_id'].nil?
          logmsg :warn, 'reject_to_group_id parameter is not set'
        end

        @group_users = Trinity::Redmine::Groups.get_group_users(params['reject_to_group_id'])
        logmsg :debug, "Group users loaded: #{@group_users}"

        if valid && @group_users.include?(issue.assigned_to.id.to_i)
          logmsg(:info, "No action needed. Assigned to user is a member of #{@group.name} group")
          valid = false
        end

        valid
      end

      def handle(issue)

        current = Trinity::Redmine::Issue.find(issue.id, :params => {:include => 'changesets,journals'})

        found = false

        last_user_id = Trinity::Redmine::Issue.get_last_user_id_from_changesets(current)
        self.notes = "Переназначено на сотрудника, который вносил изменения последним."
        issue.assigned_to_id = last_user_id
        found = true if !last_user_id.nil?

        if !found
          users = Trinity::Redmine::Issue.filter_users_from_journals_by_group_id(current, @group_users)
          last_user_id = users.sample if users.size > 0
          issue.assigned_to_id = last_user_id
          found = true if !last_user_id.nil?
        end

        if !found
          self.notes = "Мне не удалось найти сотрудника не по коммитам, не по журналу.\nВам необходимо вручную найти в истории нужного сотрудника и переназначить задачу на него."
        end

        increment_returns_field(issue)

        issue.priority_id = self.config['redmine']['priority']['critical'].to_i
        issue.notes = self.notes
        issue.fixed_version_id = ""
        issue.save

        issue
      end

      private

      def increment_returns_field(issue)
        returns_field_id = self.config['redmine']['custom_fields']['returns']
        if !returns_field_id.nil?
          returns_id = returns_field_id.to_i
          returns = issue.cf(returns_id)
          returns.value = (returns.value.to_i + 1).to_s
        end
        issue
      end

    end
  end
end