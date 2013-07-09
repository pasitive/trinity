module Trinity
  class Git
    class << self

      def status
        `git status`
      end

      def clone(repo, path)
        puts "Cloning #{repo} to #{path}"
        `git clone #{repo} #{path}`
      end

      def create_build_branch(date)
        `git checkout -b build_#{date.year}_#{date.month}_#{date.day}_#{date.hour}`
      end


      def current_branch
        `git rev-parse --abbrev-ref HEAD`
      end

      def checkout_branch(branch)
        puts "Checking out #{branch}"
        `git checkout #{branch}`
      end

    end
  end
end
