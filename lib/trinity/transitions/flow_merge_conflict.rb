# encoding: utf-8

module Trinity
  module Transitions
    class FlowMergeConflict < Transition

      attr_accessor :version

      def initialize
        super
      end

      def check(issue, params)
        valid = true

        @meta = params[:meta] if params[:meta]

        logmsg :info, "Trying to load changesets"

        @current = Trinity::Redmine::Issue.find(issue.id, :params => {:include => 'changesets'})

        logmsg :info, "Changeset are empty?: #{@current.changesets.nil?.inspect}"

        @assign_to_id = issue.assigned_to.id
        if @current.respond_to? 'changesets'
          @assign_to_id = @current.changesets.last.user.id
          self.notes = "Имеются неразрашенные конфликты.\nНеобходимо слить ветку задачи #{@meta[:related_branch]}и ветку master.\n#{@meta[:merge_message]}"
        else
          self.notes = "ВАЖНО! Нужно вручную назначить разработчика.Имеются неразрашенные конфликты.\nНужно слить ветку задачи #{@meta[:related_branch]} и ветку master.\n#{@meta[:merge_message]}"
        end

        valid
      end

      def handle(issue)
        set_issue_attributes(issue)
        issue.save
        notify_internal(issue)
        issue
      end

      private

      def set_issue_attributes(issue)
        issue.assigned_to_id = @assign_to_id
        issue.notes = self.notes
        issue.priority_id = self.config['redmine']['priority']['critical']
        issue.status_id = self.config['redmine']['status']['reopened'] # Отклонена

        issue.fixed_version_id = ''
      end

      def notify_internal(issue)
        notify = [issue.author.id, @assign_to_id]
        notify.each do |user_id|
          user = Trinity::Redmine::Users.find(user_id)
          Trinity.contact(:jabber) do |c|
            c.name = user.login
            c.to_jid = user.mail
          end
          self.notify << user.login
        end
      end

    end
  end
end