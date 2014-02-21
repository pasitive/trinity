# encoding: utf-8

module Trinity
  module Transitions
    class FlowMergeNull < Transition

      attr_accessor :version

      def initialize
        super
      end

      def check(issue, params)
        valid = true
        valid
      end

      def handle(issue)
        issue
      end

    end
  end
end
