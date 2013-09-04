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

        if issue.priority.id.to_i.eql? self.config['redmine']['priority']['critical'].to_i
          valid = false
        end

        valid
      end

      def handle(issue)

        current = Trinity::Redmine::Issue.find(issue.id, :params => {:include => 'changesets'})

        if current.changesets.last.respond_to? 'user'
          last_user_id = current.changesets.last.user.id
          self.notes = issue.notes = "Задача #{self.issue_link(issue)} отклонена.\n
                                      Необходимо ее исправить и установить статус Решена.\n
                                      Переназначено на разработчика, который делал коммит последним."
          issue.assigned_to_id = last_user_id
          user = Trinity::Redmine::Users.find(last_user_id)
        else
          self.notes = issue.notes = "Мне не удалось найти разработчика по коммитам к задаче #{self.issue_link(issue)}.\n
                                      Вероятно их никто не делал.\n
                                      Вам необходимо вручную найти в истории имя разработчика и
                                      переназначить задачу на него."
          user = Trinity::Redmine::Users.find(issue.assigned_to.id)
        end

        issue.priority_id = self.config['redmine']['priority']['critical'].to_i
        issue.save

        Trinity.contact(:jabber) do |c|
          c.name = user.login
          c.to_jid = user.mail
        end

        self.notify << user.login

        issue
      end

    end
  end
end