# encoding: utf-8

module Trinity
  module Transitions
    class Dummy < Transition

      def initialize
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