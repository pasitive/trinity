# encoding: utf-8

module Trinity
  module Transitions
    class FlowMergeDuplicate < Transition

      attr_accessor :version

      def initialize
        super
      end

      def check(issue, params)
        valid = true

        @params = params
        @meta = params[:meta] if params[:meta]

        valid
      end

      def handle(issue)

        self.notes = "Эта задача имеет более одной ветки в системе контроля версий.\n" \
                "Разработчику необходимо слить имеющиеся для задачи ветки в одну. Остальные удалить.\n" \
                "Имеющиеся ветки для задачи: #{@meta[:duplicate_branches].join(", ")}"

        issue.notes = self.notes
        issue.priority_id = self.config['redmine']['priority']['critical']
        issue.status_id = self.config['redmine']['status']['reopened'] # Отклонена
        issue.save

        issue
      end

    end
  end
end
