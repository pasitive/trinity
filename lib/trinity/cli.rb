# encoding: utf-8

module Trinity
  class CLI < Thor
    include Thor::Actions

    class_option :config, :aliases => '-c', :type => :string, :required => true
    class_option :verbose, :aliases => '-v', :type => :boolean, :default => true
    class_option :interactive, :aliases => '-i', :type => :boolean, :default => false
    class_option :hours_to_qa, :default => 2, :aliases => '-qa', :desc => "Hours to QA-team to test the build"

    @@merge_statuses = {
        :ok => 'MERGE_STATUS_OK',
        :failed => 'MERGE_STATUS_FAILED',
        :conflict => 'MERGE_STATUS_CONFLICT',
        :empty => 'MERGE_STATUS_EMPTY_RELATED_BRANCH',
    }

    @@rebuild_statuses = {
        :ok => 'REBUILD_STATUS_OK',
        :failed => 'REBUILD_STATUS_FAILED',
    }

    @@release_statuses = {
        :ok => 'RELEASE_STATUS_OK',
        :need_rebuild => 'RELEASE_STATUS_NEED_REBUILD',
        :empty_build => 'RELEASE_STATUS_EMPTY_BUILD',
    }

    TYPE_RELATES = "relates"
    TYPE_DUPLICATES = "duplicates"
    TYPE_DUPLICATED = "duplicated"
    TYPE_BLOCKS = "blocks"
    TYPE_BLOCKED = "blocked"
    TYPE_PRECEDES = "precedes"
    TYPE_FOLLOWS = "follows"
    TYPE_COPIED_TO = "copied_to"
    TYPE_COPIED_FROM = "copied_from"

    TYPES = {
        TYPE_RELATES => {:name => :label_relates_to, :sym_name => :label_relates_to,
                         :order => 1, :sym => TYPE_RELATES},
        TYPE_DUPLICATES => {:name => :label_duplicates, :sym_name => :label_duplicated_by,
                            :order => 2, :sym => TYPE_DUPLICATED},
        TYPE_DUPLICATED => {:name => :label_duplicated_by, :sym_name => :label_duplicates,
                            :order => 3, :sym => TYPE_DUPLICATES, :reverse => TYPE_DUPLICATES},
        TYPE_BLOCKS => {:name => :label_blocks, :sym_name => :label_blocked_by,
                        :order => 4, :sym => TYPE_BLOCKED},
        TYPE_BLOCKED => {:name => :label_blocked_by, :sym_name => :label_blocks,
                         :order => 5, :sym => TYPE_BLOCKS, :reverse => TYPE_BLOCKS},
        TYPE_PRECEDES => {:name => :label_precedes, :sym_name => :label_follows,
                          :order => 6, :sym => TYPE_FOLLOWS},
        TYPE_FOLLOWS => {:name => :label_follows, :sym_name => :label_precedes,
                         :order => 7, :sym => TYPE_PRECEDES, :reverse => TYPE_PRECEDES},
        TYPE_COPIED_TO => {:name => :label_copied_to, :sym_name => :label_copied_from,
                           :order => 8, :sym => TYPE_COPIED_FROM},
        TYPE_COPIED_FROM => {:name => :label_copied_from, :sym_name => :label_copied_to,
                             :order => 9, :sym => TYPE_COPIED_TO, :reverse => TYPE_COPIED_TO}
    }.freeze

    def initialize(*)
      super
      @config = Trinity::Config.load({:file => options[:config]})
      @log = Logger.new(STDOUT)
      @log.info 'Initialization - OK'
    end

    desc 'foo', 'Foo method'

    def foo

      issue = Trinity::Redmine::Issue.find(4257, :params => {:include => 'relations'})

      if !issue.respond_to? 'relations'
        nil
      else
        issues = issue.relations.select { |relation| (relation.issue_id != issue.id and relation.relation_type.to_s.eql? 'blocks') }
      end

      issues.each do |issue|
        p issue.id
      end


      issue = Trinity::Redmine::Issue.find(4257, :params => {:include => 'relations'})

      issue.relations.each do |relation|
        if TYPES[relation.relation_type]
          if relation.issue_id == issue.id
            p " + #{issue.id} #{relation.relation_type} #{relation.issue_to_id}"
          else
            p " - #{issue.id} #{TYPES[relation.relation_type][:sym]} #{relation.issue_id}"
          end
        end
      end

    end

    desc 'merge', 'Helper utility to merge branches'
    method_option :project_name, :required => true, :aliases => '-p', :desc => 'Project name'
    method_option :query_id, :required => true, :aliases => '-q', :desc => 'Query id for ready to QA features'

    def cycle

      @log.info 'Start workflow cycle'

      loop do #Global workflow loop

        if time_to_release

          @log.info "Time to release: #{Time.now.to_s}"

          versions = Trinity::Redmine::Version.fetch_versions(options[:project_name], 'locked')

          if !versions.count.eql? 0

            @log.info 'Start processing versions'

            versions.each do |version|

              @log.info "Start processing version #{version.name}"

              release_status = release options[:project_name], version.name

              case release_status

                when @@release_statuses[:empty_build]
                  version.delete
                  break

                else
                  rebuild options[:project_name], version.name, 'locked'

                  version_name = version.name
                  release_tag = version_name.split('_').drop(1).join('_')

                  `git flow release start #{version_name}`
                  `git merge --no-ff #{version_name}`
                  `git flow release finish -m '#{release_tag}' #{version_name}`
                  `git branch -d #{version_name}`
                  `git push`

                  issues = Trinity::Redmine.fetch_issues({:project_id => options[:project_name], :fixed_version_id => version.id})
                  issues.select { |i| i.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok'] }.each do |issue|
                    issue.notes = "Задача полностью реализована в версии #{version_name}"
                    issue.status_id = @config['redmine']['status']['closed']
                    issue.save
                  end

                  Trinity::Redmine::Version.prefix = '/'
                  version.status = 'closed'
                  version.save
              end

            end #end processing versions
          else
            @log.info 'No versions to release'
          end
        else
          @log.info "It's not time to release"
        end

        # Merge
        merge options[:project_name], options[:query_id]

        @log.info 'Sleep for 60 seconds'
        sleep 60

      end
    end

    desc 'merge PROJECT_NAME QUERY_ID', 'Helper utility to merge branches'

    def merge(project_name, query_id)

      log_block('Merge', 'start')

      @log.info "Project ID: #{project_name}, Query ID: #{query_id}"

      # Check if there is a current unmerged build branch.
      @log.info 'Check if there is current build branch'
      regex = /\A\*?\s?build_.*\Z/
      build = `git branch -a`.split("\n").map { |n| n.strip.gsub('* ', '') }.select { |a| regex.match(a) }.last

      build = prepare_build(project_name, build)
      version = Trinity::Redmine::Version.find_version(project_name, build)

      if version.nil?
        @log.warn 'Version is nil'
        return false
      end

      # Prevent merging to master
      if Trinity::Git.current_branch.match('master')
        @log.warn 'Current branch is master. STOP MERGING DIRECTLY TO MASTER BRANCH'
        return false
      end

      @log.info "Current branch is: #{Trinity::Git.current_branch}"

      @log.info 'Merging master into current branch'
      `git merge master`

      @log.info 'Begin merging features'

      @log.info 'Fetching issues and remote branches'
      issues_to_build = Trinity::Redmine.fetch_issues_by_filter_id(query_id, {:project_id => project_name})

      @log.info "Issues loaded: #{issues_to_build.count.to_s}"

      issues_to_build.each do |issue|

        log_block("Feature #{issue.id} merge", 'start')

        ret = merge_feature_branch(issue, version)

        issue = ret[:issue]
        status = ret[:merge_status]

        if status.eql? @@merge_statuses[:ok]
          @log.info 'Changing issue parameters'
          @log.info "Version ID: #{version.id}"
          # Adding issue into build
          issue.fixed_version_id = version.id
          @log.info "Status ID: #{@config['redmine']['status']['on_prerelease']}"
          issue.status_id = @config['redmine']['status']['on_prerelease']
        elsif status.eql? @@merge_statuses[:conflict]
          issue.priority_id = @config['redmine']['priority']['critical']
          @log.info "Status ID: #{@config['redmine']['status']['reopened']}"
          issue.status_id = @config['redmine']['status']['reopened'] # Отклонена
        end

        @log.info "Saving issue"
        issue.save

        @log.info status.inspect if options[:verbose]

        # @todo change status & fixed_version_id of related issues

        log_block("Feature #{issue.id} merge", 'end')

        sleep 2
      end

      `git push origin #{build}`

      log_block('Merge', 'end')

      return true
    end

    desc 'rebuild PROJECT_NAME BRANCH_NAME', 'Helper utility to rebuild build branches'

    def rebuild(project_name, branch, status = 'open')

      log_block('Rebuild', 'start')

      version = Trinity::Redmine::Version.find_version project_name, branch, status

      if !version.nil?
        @log.info "Found version: #{version.name} (#{version.id}) [#{version.status}]"
        version_id = version.id.strip.to_i

        @log.info 'Preparing build branch'

        `git checkout master`
        `git branch -D #{branch}`
        `git push origin :#{branch}` if Trinity::Git.is_branch_pushed(branch)
        `git checkout -b #{branch}`

        issues = Trinity::Redmine.fetch_issues({:project_id => project_name, :fixed_version_id => version_id})
        @log.info "Loaded issues: #{issues.count.to_s}"

        issues.each do |issue|
          @log.info "Processing issue: #{issue.id} #{issue.subject}"
          @log.info "Is status correct (On prerelease - OK)?: #{issue.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok']}"

          # On prerelease (Status id: 16), On prerelease - OK (Status id: 15)
          correct_status = [
              @config['redmine']['status']['on_prerelease_ok']
          ]

          if correct_status.include?(issue.status.id.to_i)
            @log.info "Merging issue: #{issue.id} v#{issue.fixed_version.name}"

            ret = merge_feature_branch(issue, version)

            issue.save if !ret[:merge_status].eql? @@merge_statuses[:ok]

            @log.info ret[:merge_status]
          else
            issue.fixed_version_id = ''
            @log.info "Removing fixed_version_id: #{issue.fixed_version.id}"

            issue.notes = 'Задача была отклонена. В билд не попадает.'
            @log.info "Adding notes: #{issue.notes}"

            @log.info "Saving issue"
            issue.save
          end
        end

        `git push origin #{branch}`

      else
        @log.warn "Couldn't find version you supplied"
      end

      log_block('Rebuild', 'end')

      return @@rebuild_statuses[:ok]
    end

    desc 'release PROJECT_NAME', 'Release helper utility'

    def release(project_name, version)

      version = Trinity::Redmine::Version.find_version(project_name, version, 'locked')

      log_block("Release #{version.name}", 'start')

      version_name = version.name

      `git checkout #{version_name}`

      issues = Trinity::Redmine.fetch_issues({:project_id => project_name, :fixed_version_id => version.id.to_i})
      @log.info "Loaded issues: #{issues.count.to_s}" if options[:verbose]

      # Check if all issues has right status
      if issues.any? { |i| !i.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok'] }

        @log.warn 'We have issues that do not match release status'

        issues.select { |i| !i.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok'] }.each do |issue|
          issue.fixed_version_id = ''
          issue.notes = "Задача не попадает в билд #{version.name}. Имеет неверный статус."
          issue.save
        end

        return @@release_statuses[:need_rebuild]
      elsif issues.count.eql? 0
        @log.warn 'No issues for build'
        return @@release_statuses[:empty_build]
      else
        @log.info 'Do not need to rebuild'

        return @@release_statuses[:ok]
      end

      log_block('Release', 'end')

    end

    private

    def prepare_build(project_name, build)

      log_block('Prepare', 'start')

      ret = {
          :build => nil,
          :version => nil
      }

      @log.info 'Fetching changes from origin'
      `git fetch origin`
      @log.info 'Current branch is: %s' % Trinity::Git.current_branch

      # Choosing time for new build branch
      date = choose_date()

      # If there is no current build, create it.
      # Otherwise process current build.
      # Checklist:
      #  * if build pushed & merged, delete build branch and exit the loop
      #  * if build not pushed & not merged, begin merging features
      #  * if build pushed & not merged but it is time to QA - push build and delete local branch
      if build.nil?
        @log.info 'No current build'

        build_name = "build_#{date.year}_#{date.month}_#{date.day}_#{date.hour}"

        build = Trinity::Git.create_build_branch(date)
        version = Trinity::Redmine.create_version(project_name, build)

        @log.info "Created new build branch #{build_name}"

        return build
      else

        @log.info "We have build #{build}"

        version = Trinity::Redmine::Version.find_version(project_name, build)

        if version.nil?
          version = Trinity::Redmine.create_version(project_name, build)
        end

        @log.info "Found version: #{version.name}"

        if version.nil?
          @log.fatal 'No version found or loaded'
          abort
        end

        build_pushed = Trinity::Git.is_branch_pushed(build)
        @log.info "Check if build is pushed to origin: #{build_pushed.inspect}"

        build_merged = Trinity::Git.is_branch_merged(build, 'master')
        @log.info "Check if build is already merged: #{build_merged.inspect}"

        build_has_no_issues = Trinity::Redmine.fetch_issues({:project_id => project_name, :fixed_version_id => version.id.to_i}).count.eql? 0
        @log.info "Build has NO issues: #{build_has_no_issues.inspect}"

        if build_pushed

          @log.info 'Build pushed to origin'

          if build_merged and build_has_no_issues
            # New empty build
            @log.info "Build #{build} has no issues. Switching to #{build} and start merging features"
            `git checkout #{build}`
          elsif !build_merged
            # New empty build
            @log.info "Build #{build} is NOT MERGED to master. Switching to #{build} and start merging features"
            `git checkout #{build}`
          else
            @log.info "Build #{build} is MERGED to master and PUSHED to origin"

            `git branch -d #{build}`
            @log.info "Deleted build branch #{build}"

            build = Trinity::Git.create_build_branch(date)
            @log.info "Created new build branch: #{build}"

            return build
          end

        else
          @log.info 'Build NOT pushed to origin. Now pushing'
          `git push origin #{build}`
        end

        time_to_qa = time_to_qa(build, options[:hours_to_qa])
        @log.info "Is it time to QA build?: #{time_to_qa}"

        if time_to_qa

          @log.info 'Time to QA build.'

          @log.info 'Locking version'
          Trinity::Redmine::Version.prefix = '/'
          version.status = 'locked'
          version.save

          `git push origin #{build}`
          `git checkout master`
          `git branch -D #{build}`

          @log.info "Deleted branch #{build}"

          @log.info "Sending notifications to #{@config['notification']['recepients'].join(',')}"
          @config['notification']['recepients'].each do |recipient|
            Mail.deliver do
              from 'trinity@happylab.ru'
              to recipient
              subject "#{project_name} // build info"
              content_type 'text/html; charset=UTF-8'
              body "Build <a href='http://r.itcreativoff.com/versions/#{version.id}'>#{build}</a> is ready for QA in http://tvkinoradio.pre.itcreativoff.com"
            end
            @log.info "The message was send to #{recipient}" if options[:verbose]
          end

        else
          `git checkout #{build}`
        end

        log_block('Prepare', 'end')
        return build
      end

    end

    def merge_feature_branch(issue, version)

      ret = {
          :issue => issue,
          :merge_status => @@merge_statuses[:ok]
      }

      related_branch = Trinity::Git.find_issue_related_branch(issue)

      @log.info "Related branch: #{related_branch}"

      if !related_branch.empty?

        @log.info 'Merging branch'
        branch_merged = `git branch -r --merged`.split("\n").map { |br| br.strip }.select { |br| related_branch.match(br) }

        if branch_merged.empty?
          @log.info "Merging #{issue.id} branch #{related_branch}"

          merge_status = `git merge --no-ff #{related_branch}`

          @log.info merge_status

          conflict = /CONFLICT|fatal/

          if conflict.match(merge_status)

            @log.warn "Error while automerging branch #{related_branch}"
            puts "Resetting HEAD"
            `git reset --hard`

            @log.info "Trying to load changesets"
            current = Trinity::Redmine::Issue.find(issue.id, :params => {:include => 'changesets'})
            @log.info "Changeset loaded: #{!current.changesets.nil?.inspect}" if options[:verbose]

            # Try to assign developer
            if !current.changesets.empty? && current.changesets.last.user.id
              @log.info "Assigned to ID: #{current.assigned_to.id}"
              @log.info "Changeset last user ID: #{current.changesets.last.user.id}"
              issue.assigned_to_id = current.changesets.last.user.id
              issue.notes = "Имеются неразрашенные конфликты.\nНеобходимо слить ветку задачи #{related_branch} и ветку master.\n#{merge_status}"
            else
              issue.notes = "Имеются неразрашенные конфликты.\nНужно слить ветку задачи #{related_branch} и ветку master.\n#{merge_status}"
            end

            ret[:merge_status] = @@merge_statuses[:conflict]
          else
            ret[:merge_status] = @@merge_statuses[:ok]
          end

        else
          @log.info 'Branch already merged. Next...'
        end

      else
        ret[:merge_status] = @@merge_statuses[:empty]
      end

      ret[:issue] = issue

      return ret
    end

    def time_to_release
      Time.now.hour >= 17
    end

    def choose_date
      now = Time.now
      if now.hour < (17-options[:hours_to_qa].to_i)
        date = Chronic.parse('today at 17pm')
      else
        date = Chronic.parse('tomorrow at 17pm')
      end

      if date.nil?
        @log.error "#{__method__}: Chronic.parse error"
        abort
      end

      @log.info "Date for build: #{date}; Hours to QA: #{options[:hours_to_qa]}"
      return date
    end

    def time_to_qa(build, hours_diff)

      @log.info "Hours diff: #{hours_diff}"
      @log.info "Build: #{build}"

      # Parse date from build name
      buf = build.split('_').drop(1)
      date_buf = buf.take(3).join('-').concat ' '
      time_buf = buf.last
      date_string = date_buf.concat(time_buf)
      parsed_date = Chronic.parse(date_string)

      if parsed_date.nil?
        @log.fatal "#{__method__} couldn't parse time"
        abort
      end

      @log.info "#{__method__}: #{parsed_date}"

      (parsed_date-Time.now)/3600.round <= hours_diff
    end

    def log_block(name, state)
      @log.info "[============================= #{name}: #{state} ===============================]"
    end

  end
end
