# encoding: utf-8

module Trinity
  module Transitions
    class FlowAuthorCheck < Transition

      attr_accessor :version

      def initialize
        super
      end

      def check(issue, params)
        valid = true



        if valid && (issue.assigned_to.id.eql? issue.author.id and issue.status.id.to_i.eql? @config['redmine']['status']['author_check'])
          valid = false
        end

        valid
      end

      def handle(issue)

        issue.notes = "Задача ##{issue.id} полностью реализована и готова к проверке автором."
        issue.status_id = @config['redmine']['status']['author_check']
        issue.assigned_to_id = issue.author.id

        issue.save
        issue
      end

    end
  end
end