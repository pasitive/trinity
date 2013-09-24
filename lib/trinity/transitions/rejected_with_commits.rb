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

        #if valid && (issue.priority.id.to_i.eql? self.config['redmine']['priority']['critical'].to_i)
        #  valid = false
        #end

        # Check if group valid
        @group = Trinity::Redmine::Groups.find(params['reject_to_group_id'], :params => {:include => 'users'})

        if !@group.respond_to? 'name'
          applog(:warn, "Group #{params['reject_to_group_id']} not found")
          valid = false
        end

        if valid && (!@group.respond_to? 'users')
          applog(:warn, "No users in group #{@group.name}")
          valid = false
        end

        @group_users = @group.users.inject([]) do |result, user|
          result << user.id.to_i
          result
        end

        if valid && @group_users.empty?
          applog(:warn, "No users in group #{@group.name}")
          valid = false
        end

        if valid && @group_users.include?(issue.assigned_to.id.to_i)
          applog(:info, "No action needed. Assigned to user is a member of #{@group.name} group")
          valid = false
        end

        valid
      end

      def handle(issue)

        current = Trinity::Redmine::Issue.find(issue.id, :params => {:include => 'changesets'})

        if current.respond_to? 'changesets'
          if current.changesets.last.respond_to? 'user'
            last_user_id = current.changesets.last.user.id
            self.notes = "Задача #{self.issue_link(issue)} отклонена.\n
                                      Необходимо ее исправить и установить статус Решена.\n
                                      Переназначено на разработчика, который делал коммит последним."
            issue.assigned_to_id = last_user_id
            user = Trinity::Redmine::Users.find(last_user_id)
          else
            self.notes = "Мне не удалось найти разработчика по коммитам к задаче #{self.issue_link(issue)}.\n
                                      Вероятно их никто не делал.\n
                                      Вам необходимо вручную найти в истории имя разработчика и
                                      переназначить задачу на него."
            user = Trinity::Redmine::Users.find(issue.assigned_to.id)
          end
        else
          self.notes = 'Задача отклонена.'
        end

        if !self.config['redmine']['custom_fields']['returns'].nil?
          returns_id = self.config['redmine']['custom_fields']['returns'].to_i
          returns = issue.cf(returns_id)
          returns.value = (returns.value.to_i + 1).to_s
        end

        issue.priority_id = self.config['redmine']['priority']['critical'].to_i
        issue.notes = self.notes
        issue.save

        #Trinity.contact(:jabber) do |c|
        #  c.name = user.login
        #  c.to_jid = user.mail
        #end
        #
        #self.notify << user.login

        issue
      end

    end
  end
end