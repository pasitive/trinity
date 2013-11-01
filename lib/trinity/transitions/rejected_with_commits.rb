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

        if current.respond_to? 'changesets'
          if current.changesets.last.respond_to? 'user'
            last_user_id = current.changesets.last.user.id
            self.notes = "Задача #{self.issue_link(issue)} отклонена.\r\n
                                      Необходимо ее исправить и установить статус Решена.\r\n
                                      Переназначено на разработчика"
            issue.assigned_to_id = last_user_id
            user = Trinity::Redmine::Users.find(last_user_id)
          else

            if current.respond_to? 'journals'
              devs = current.journals.inject([]) do |result, journal|
                result << journal.user.id.to_i if (@group_users.include? journal.user.id.to_i)
                result
              end
              devs.uniq!
              if devs.size > 0
                issue.assigned_to_id = devs.sample
              end
            else
              self.notes = "Мне не удалось найти разработчика по коммитам к задаче #{self.issue_link(issue)}. \r\n
                            Вероятно их никто не делал. \r\n
                            Вам необходимо вручную найти в истории имя разработчика и переназначить задачу на него."
            end
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

        issue
      end


      def try_find_in_journals(issue)
        issue = Trinity::Redmine::Issue.find(4687, :params => {:include => 'journals'})

        group = Trinity::Redmine::Groups.find(reject_ro_group_id, :params => {:include => 'users'})
        group_users = group.users.inject([]) do |result, user|
          result << user.id.to_i
          result
        end


      end

    end
  end
end