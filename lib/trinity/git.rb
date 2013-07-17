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

      def is_branch_pushed(branch)
        !`git branch -r`.split("\n").map { |n| n.strip.gsub('* ', '') }.select { |b| b.match(branch) }.empty?
      end

      def is_branch_merged(branch)
        !`git branch -r --merged`.split("\n").map { |n| n.strip }.select { |b| b.match(branch) }.empty?
      end

    end
  end
end
