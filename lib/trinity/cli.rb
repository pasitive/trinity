# encoding: utf-8

module Trinity
  class CLI < Thor
    include Thor::Actions

    class_option :config, :aliases => '-c', :type => :string
    class_option :verbose, :aliases => '-v', :type => :boolean, :default => true
    class_option :hours_to_qa, :default => 2, :aliases => '-qa', :desc => "Hours to QA-team to test the build"

    @@merge_statuses = {
        :ok => 'MERGE_STATUS_OK',
        :failed => 'MERGE_STATUS_FAILED',
        :conflict => 'MERGE_STATUS_CONFLICT',
        :empty => 'MERGE_STATUS_EMPTY_RELATED_BRANCH',
        :already_merged => 'MERGE_STATUS_ALREADY_MERGED',
        :duplicate_branch => 'MERGE_STATUS_DUPLICATE_BRANCH',
    }.freeze

    @@rebuild_statuses = {
        :ok => 'REBUILD_STATUS_OK',
        :failed => 'REBUILD_STATUS_FAILED',
    }.freeze

    @@release_statuses = {
        :ok => 'RELEASE_STATUS_OK',
        :need_rebuild => 'RELEASE_STATUS_NEED_REBUILD',
        :empty_build => 'RELEASE_STATUS_EMPTY_BUILD',
    }.freeze

    TYPE_BLOCKS = "blocks"
    TYPE_BLOCKED = "blocked"

    TYPES = {
        TYPE_BLOCKS => {:name => :label_blocks, :sym_name => :label_blocked_by,
                        :order => 4, :sym => TYPE_BLOCKED},
        TYPE_BLOCKED => {:name => :label_blocked_by, :sym_name => :label_blocks,
                         :order => 5, :sym => TYPE_BLOCKS, :reverse => TYPE_BLOCKS},
    }.freeze

    def initialize(*)
      super
      # Loading config file
      @config = Trinity::Config.load({:file => options[:config]})
    end

    desc 'version', 'Get version number'

    def version
      p VERSION.to_s
    end

    desc 'tmpreport', 'Report generator tmp'

    def tmpreport(query_id)
      issues = Trinity::Redmine.fetch_issues_by_filter_id(query_id, {})
      webdev_users = Trinity::Redmine::Groups.get_group_users(18) #Web development

      logmsg(:info, "Loaded issues: #{issues.count}")

      summary = []

      issues.each do |issue|

        current = Trinity::Redmine::Issue.find(issue.id, :params => {:include => 'changesets,journals'})

        users = Trinity::Redmine::Issue.filter_users_from_journals_by_group_id(current, webdev_users)
        last_user_id = users.sample if users.size > 0
        issue.assigned_to_id = last_user_id
        found = true if !last_user_id.nil?

        buf = {
            last_user_id: last_user_id,
            issue: issue,
        }

        summary.push(buf);

        # summary[issue.id.to_i] = {last_user_id: last_user_id}
        puts "##{issue.id}: last_user_id: #{last_user_id}"
      end

      puts "Summary total items: #{summary.count}"

      summary = summary.group_by { |b| b[:last_user_id] }

      #puts "================="
      #puts summary[70].count
      #exit

      u = Trinity::Redmine::Users.find(:all, :params => {:group_id => 18})

      u.each do |user|

        full_name = user.firstname + " " + user.lastname

        if !summary.has_key? user.id.to_i
          puts "Не найдено задач для пользователя: #{full_name}"
          next
        end
        puts "#{full_name}. Задач закрыто: #{summary[user.id.to_i].count}"
      end

    end

    desc 'transition', 'Utility to help handle issue statuses and assign issues to the employers'

    def transition
      loop do
        begin
          @config['transitions'].each do |project, transitions|
            logmsg(:info, "Processing project: #{project}")
            transitions.each do |tn, params|

              next if tn.eql? "config"

              t = Trinity::Transition.generate(tn)
              logmsg(:info, "Processing transition #{t.friendly_name}")
              t.config = @config

              if project.to_s.eql? 'all'
                issues = Trinity::Redmine.fetch_issues_by_filter_id(params['query_id'], {})
              else
                issues = Trinity::Redmine.fetch_issues_by_filter_id(params['query_id'], {:project_id => project})
              end

              logmsg(:info, "Issues loaded: #{issues.count}")

              issues.each do |issue|
                check = t.check(issue, params)
                t.handle(issue) if check
                notify(t.notify, t.notes) if check
              end

            end
          end
        rescue ActiveResource::ServerError => e
          msg = "We have problem while handling response from Redmine server. Sleep for a while."
          notify('admins', msg)
          sleep 60
        rescue Exception => e
          msg = "#{e.message} #{e.backtrace}"
          logmsg(:error, msg)
          notify('admins', msg)
        ensure
          puts "Sleep for a while..."
          sleep 30
        end
      end
    end

    desc 'cycle', 'Main workflow cycle'
    method_option :project_name, :required => true, :aliases => '-p', :desc => 'Project name'
    method_option :query_id, :required => true, :aliases => '-q', :desc => 'Query id for ready to QA features'
    method_option :release_locked, :default => false, :aliases => '-r', :desc => 'Release locked versions'

    def cycle
      logmsg :info, 'Start workflow cycle'
      loop do #Global workflow loop

        logmsg :info, 'START: Processing locked versions'
        versions = Trinity::Redmine::Version.fetch_versions(options[:project_name], 'locked')
        if !versions.count.eql? 0
          versions.each do |version|
            logmsg :info, "Start processing version #{version.name}"

            version_name = version.name
            release_tag = version_name.split('_').drop(1).join('_')

            release_status = @@release_statuses[:ok]

            invoke :rebuild, [options[:project_name], version.name, 'locked'],
                   :force => true,
                   :skip_status => true,
                   :config => options[:config]

            release_status_message = ""
            release_status_message += `git flow release start #{version_name}`
            release_status_message += `git merge --no-ff #{version_name}`
            release_status_message += `git flow release finish -m '#{release_tag}' #{version_name}`
            release_status_message += `git branch -d #{version_name}`
            release_status_message += `git push`

            notify('admins', release_status_message)

            issues = Trinity::Redmine.fetch_issues({
                                                       :project_id => options[:project_name],
                                                       :fixed_version_id => version.id})
            issues.each do |issue|
              t = Trinity::Transition.generate('flow_author_check')
              t.config = @config
              t.version = version
              t.handle(issue) if t.check(issue, {})
            end

            Trinity::Redmine::Version.prefix = '/'
            version.status = 'closed'
            version.save

          end #end processing versions
        else
          logmsg :info, 'No locked versions'
        end
        logmsg :info, 'END: Processing locked versions'


        logmsg :info, 'START: Processing open versions custom fields'
        # Custom build operations
        versions = Trinity::Redmine::Version.fetch_versions(options[:project_name], 'open')
        if !versions.count.eql? 0
          # rebuild logic
          versions.each do |version|
            # @TODO вынести forced_rebuild_prop в конфиг
            forced_rebuild_prop = version.get_cf(20)
            if !forced_rebuild_prop.nil?
              forced_rebuild_prop_value = forced_rebuild_prop.value
              case forced_rebuild_prop_value
                when 'once' then
                  invoke :rebuild, [options[:project_name], version.name], :force => true, :skip_status => true, :config => options[:config]
                  Trinity::Redmine::Version.prefix = '/'
                  forced_rebuild_prop.value = nil
                  version.save
              end
            end
          end
        else
          logmsg :info, 'No version with force rebuild=>true'
        end
        logmsg :info, 'END: Processing open versions custom fields'

        # Merge
        merge options[:project_name], options[:query_id]

        logmsg :info, 'Sleep for 30 seconds'
        sleep 30
      end
    end

    desc 'merge PROJECT_NAME QUERY_ID', 'Helper utility to merge branches'

    def merge(project_name, query_id)
      read_git_flow_config

      log_block('Merge', 'start')

      logmsg :info, "Project ID: #{project_name}, Query ID: #{query_id}"

      # Check if there is a current unmerged build branch.
      logmsg :info, 'Check if there is current build branch'
      regex = /\A\*?\s?build_.*\Z/
      build = `git branch -a`.split("\n").map { |n| n.strip.gsub('* ', '') }.select { |a| regex.match(a) }.last

      build = prepare_build(project_name, build)

      Trinity::Git::fetch
      Trinity::Git::prune

      version = Trinity::Redmine::Version.find_version(project_name, build)

      if version.nil?
        logmsg :warn, 'Version is nil'
        return false
      end

      # Prevent merging to master
      if Trinity::Git.current_branch.match(@master_branch)
        logmsg :warn, "Current branch is #{@master_branch}. Stop merging directly into #{@master_branch}"
        `git checkout #{build}`
      end

      logmsg :info, "Current branch is: #{Trinity::Git.current_branch}"

      logmsg :info, 'Pulling changes into current branch'
      `git branch --set-upstream-to=origin/#{build} #{build}`
      `git pull`

      logmsg :info, "Merging #{@master_branch} into current branch"
      merge_status = `git merge --no-ff origin/#{@master_branch}`

      return false if is_conflict(merge_status, ['project' => project_name, 'current_branch' => Trinity::Git.current_branch, 'merging_branch' => "origin/#{@master_branch}"])

      logmsg :info, 'Begin merging features'

      logmsg :info, 'Fetching issues and remote branches'
      issues_to_build = Trinity::Redmine.fetch_issues_by_filter_id(query_id, {:project_id => project_name})

      logmsg :info, "Issues loaded: #{issues_to_build.count.to_s}"

      issues_to_build.each do |issue|

        log_block("Feature #{issue.id} merge", 'start')

        ret = merge_feature_branch(issue, version, project_name)
        handle_merge_status(issue, ret[:version], ret)

        build = ret[:version]

        log_block("Feature #{issue.id} merge", 'end')
        sleep 2
      end

      `git push origin #{build}`

      log_block('Merge', 'end')

      return true
    end

    desc 'gcb PROJECT_NAME', 'Garbage collector for builds'

    def gcb(project_name)
      regexp = /build_*/
      remote_branch_list = `git branch -r`.split("\n").map { |n| n.strip }.select { |a| regexp.match(a) }
      # Normolize
      remote_branch_list = remote_branch_list.map { |b| b.split('/').drop(1).join }

      #p remote_branch_list

      Trinity::Redmine::Version.prefix = '/projects/' + project_name + '/'
      buf = Trinity::Redmine::Version.find(:all)

      # Normolize
      builds = buf.select { |b| b.name.match(/build_*$/) }

      builds_to_delete = []
      remote_branch_list.each do |build|

        name = build
        build_obj = builds.select { |b| b.name.match(build) }.first

        if build_obj.nil?
          p "Build #{name} is in trash. Ready to delete"
          builds_to_delete.push(':' + name)
        else
          if build_obj.status.eql? 'closed'
            p "Build #{name} has status #{build_obj.status}. Ready to delete"
            builds_to_delete.push(':' + name)
          end
        end

      end

      `git push origin #{builds_to_delete.join(' ')}`

    end

    desc 'gc QUERY_ID', 'Garbage collector'

    def gc(query_id)

      offset = 0
      limit = 100
      stat = {
          :total_issues => 0,
          :total_branches => 0,
          :total_builds => 0,
          :found_remotes_for => 0,
          :proc => 0, # total issues processed
          :del => 0, # total branches deleted
          :not_merged => 0, # total branches bot merged
          :not_merged_ids => [],
      }

      regexp = /origin\/feature\/[0-9]+_*/
      remote_branch_list = `git branch -r`.split("\n").map { |n| n.strip }.select { |a| regexp.match(a) }
      issue_list = []

      stat[:total_branches] = remote_branch_list.count

      loop do
        begin
          buf = Trinity::Redmine.fetch_issues_by_filter_id(query_id, {:offset => offset, :limit => limit})
          # Normolizing
          issue_list.push(buf)
          raise StandardError if buf.count.eql? 0
        rescue StandardError => e
          break
        ensure
          offset += limit
          logmsg :info, "--> Increment offset"
        end
      end


      issue_list.flatten!

      features_to_delete = []
      remote_branch_list.each do |branch|
        logmsg :debug, "Processing branch #{branch}"
        buf = branch.match(/([0-9]+)_*/)
        related_issue_id = buf[1].to_i
        issue = issue_list.find { |i| i.id.to_i.eql? related_issue_id }
        if !issue.nil?
          stat[:found_remotes_for]+=1
          branch_merged = !`git branch -r --merged | grep #{related_issue_id}`.split("\n").map { |i| i.strip }.empty?
          logmsg :debug, "--> Merged?:" + (branch_merged).to_s

          if !branch_merged
            stat[:not_merged]+=1
            stat[:not_merged_ids].push(issue.id.to_i)
          else
            features_to_delete.push(':' + branch.split('/').drop(1).join('/'))
          end

          logmsg :debug, "--> for branch #{branch} found CLOSED ##{related_issue_id} (issue status_id: #{issue.status.id})"
        else
          #logmsg :warn, "--> NOT found closed issue for branch #{branch}"

        end
      end

      logmsg :info, "Deleting #{features_to_delete.count} branches: "

      `git push origin #{features_to_delete.join(' ')}`

      stat[:total_issues] = issue_list.count

      p stat
    end

    desc 'rebuild PROJECT_NAME BRANCH_NAME STATUS', 'Helper utility to rebuild build branches'
    method_option :skip_status, :default => false, :type => :boolean, :aliases => '-s', :desc => 'Skip statuses'
    method_option :force, :default => false, :type => :boolean, :aliases => '-f', :desc => 'Delete branch completely and merge features again. Use with caution.'

    def rebuild(project_name, branch, status = 'open')

      read_git_flow_config

      log_block('Rebuild', 'start')

      version = Trinity::Redmine::Version.find_version project_name, branch, status

      if !version.nil?
        logmsg :info, "Found version: #{version.name} (id:#{version.id}) [#{version.status}]"
        version_id = version.id.strip.to_i

        logmsg :info, 'Preparing build branch'

        if options[:force]
          #logmsg :info, "Checkout #{branch}"
          `git checkout #{branch}`

          #logmsg :info, "Checkout #{@master_branch}"
          `git checkout #{@master_branch}`

          #logmsg :info, "Deleting local branch #{branch}"
          `git branch -D #{branch}` if `git branch`.split("\n").map { |b| b.strip }.include?(branch)

          #logmsg :info, "Pushing local branch #{branch}"
          `git push origin :#{branch}` if Trinity::Git.is_branch_pushed(branch)

          #logmsg :info, "Creating new branch #{branch}"
          `git checkout -b #{branch}`

          #logmsg :info, "Pushing to origin #{branch}"
          `git push origin #{branch}`
        end

        `git checkout #{branch}`

        Trinity::Git::fetch

        #`git pull origin/#{branch}`
        merge_status = `git merge origin/#{@master_branch}`

        if is_conflict(merge_status)
          message = "rebuild conflict while merging master\n#{merge_status}"
          `git reset --hard` if is_conflict(merge_status)
          notify('admins', message)
        end

        # Prevent merging to master
        if Trinity::Git.current_branch.match(@master_branch)
          message = "REBUILD: Current branch is #{@master_branch}. Stop merging directly into #{@master_branch}"
          logmsg :warn, message
          notify('admins', message)
          return false
        end

        issues = Trinity::Redmine.fetch_issues({:project_id => project_name, :fixed_version_id => version_id})
        logmsg :info, "Loaded issues: #{issues.count.to_s}"

        issues.each do |issue|
          logmsg :info, "Processing issue: #{issue.id} #{issue.subject}"
          logmsg :info, "Is status correct (On prerelease - OK)?: #{issue.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok']}"

          correct_status = [
              @config['redmine']['status']['on_prerelease_ok']
          ]

          if correct_status.include?(issue.status.id.to_i) or options[:skip_status]

            logmsg :info, "Merging issue: #{issue.id} v#{issue.fixed_version.name}"

            ret = merge_feature_branch(issue, version, project_name)

            if status.eql? @@merge_statuses[:conflict]
              t = Trinity::Transition.generate('flow_merge_conflict')
              t.config = @config
              t.version = ret[:version]
              t.handle(issue) if t.check(issue, ret)
            end

            logmsg :info, ret[:merge_status]
          else
            t = Trinity::Transition.generate('flow_reject_from_build')
            t.config = @config
            t.version = ret[:version]
            t.handle(issue) if t.check(issue, ret)
          end
        end

        `git push origin #{branch}`

      else
        logmsg :warn, "Couldn't find version you supplied"
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

      logmsg :info, "Loaded issues: #{issues.count.to_s}"

      # Check if all issues has right status
      if issues.any? { |i| !i.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok'] }
        logmsg :info, 'Some issues in the build are in incorrect status'
        issues.select { |i| !i.status.id.to_i.eql? @config['redmine']['status']['on_prerelease_ok'] }.each do |issue|
          t = Trinity::Transition.generate('flow_reject_from_build')
          t.config = @config
          t.version = version
          t.handle(issue) if t.check(issue, {})
        end
        return @@release_statuses[:need_rebuild]
      elsif issues.count.eql? 0
        logmsg :warn, 'No issues for build'
        return @@release_statuses[:empty_build]
      else
        logmsg :info, 'Do not need to rebuild'
        return @@release_statuses[:ok]
      end

      log_block('Release', 'end')
    end

    private

    def handle_merge_status(issue, version, ret)

      logmsg :debug, "Version to handle: #{version.name}"

      case ret[:merge_status]
        when @@merge_statuses[:ok]
          t = Trinity::Transition.generate('flow_merge_ok')
        when @@merge_statuses[:conflict]
          t = Trinity::Transition.generate('flow_merge_conflict')
        when @@merge_statuses[:already_merged]
          t = Trinity::Transition.generate('flow_merge_null')
        when @@merge_statuses[:duplicate_branch]
          t = Trinity::Transition.generate('flow_merge_duplicate')
        else
          t = Trinity::Transition.generate('flow_merge_ok')
      end

      if t.nil? and !@@merge_statuses[:already_merged]
        msg = "Could not generate Transition"
        logmsg(:fatal, msg)
        notify('admins', msg)
        abort
      end

      t.config = @config
      t.version = version
      t.handle(issue) if t.check(issue, ret)
    end

    def merge_feature_branch(issue, version, project_name)

      ret = {
          :project_name => project_name,
          :version => version,
          :issue => issue,
          :merge_status => @@merge_statuses[:ok],
          :meta => {}
      }

      related_branches = Trinity::Git.find_issue_related_branch(issue)

      # If issue has ONLY 1 branch - merge it.
      # Otherwise message about it into related issue
      if related_branches.size.to_i <= 1
        related_branch = related_branches.join
        logmsg :info, "Related branch: #{related_branch}"

        if issue.respond_to?(:fixed_version)

          logmsg :info, "Merging branch into build it assigned to"

          current_version_id = ret[:version].id
          issue_version_id = issue.fixed_version.id

          logmsg :debug, "Current build: #{version.name} (id: #{current_version_id})"
          logmsg :debug, "Merged branch version: #{issue.fixed_version.name} (id: #{issue_version_id})"

          logmsg :debug, "Equal versions: #{current_version_id.eql? issue_version_id}"

          if !current_version_id.eql? issue_version_id
            ret[:version] = issue.fixed_version
            `git checkout #{issue.fixed_version.name}`
          end

        end

        if !related_branch.empty?

          logmsg :info, 'Merging branch'
          branch_merged = `git branch -r --merged`.split("\n").map { |br| br.strip }.select { |br| related_branch.match(br) }

          if branch_merged.empty?

            logmsg :info, "Merging #{issue.id} branch #{related_branch} into #{ret[:version].name}"

            merge_status = `git merge --no-ff #{related_branch}`

            logmsg :info, merge_status

            conflict = /CONFLICT|fatal/

            if conflict.match(merge_status)
              logmsg :warn, "Error while automerging branch #{related_branch}"
              logmsg :info, 'Resetting HEAD'
              `git reset --hard`
              ret[:merge_status] = @@merge_statuses[:conflict]
              ret[:meta] = {
                  :related_branch => related_branch,
                  :merge_message => merge_status,
              }
            else
              ret[:merge_status] = @@merge_statuses[:ok]
            end

          else
            logmsg :info, 'Branch already merged. Next...'
            ret[:merge_status] = @@merge_statuses[:ok]
          end

        else
          ret[:merge_status] = @@merge_statuses[:empty]
        end

      else
        ret[:merge_status] = @@merge_statuses[:duplicate_branch]
        ret[:meta] = {
            :duplicate_branches => related_branches
        }
      end

      ret[:issue] = issue

      return ret
    end

    def prepare_build(project_name, build)

      read_git_flow_config

      log_block('Prepare', 'start')

      ret = {
          :build => nil,
          :version => nil
      }

      logmsg :info, 'Fetching changes from origin'
      Trinity::Git.fetch
      logmsg :info, 'Current branch is: %s' % Trinity::Git.current_branch

      # Choosing time for new build branch
      date = choose_date()

      # If there is no current build, create it.
      # Otherwise process current build.
      # Checklist:
      #  * if build pushed & merged, delete build branch and exit the loop
      #  * if build not pushed & not merged, begin merging features
      #  * if build pushed & not merged but it is time to QA - push build and delete local branch

      if build.nil?
        logmsg :info, 'No current build'
        build_name = "build_#{date.year}_#{date.month}_#{date.day}_#{date.hour}"
        build = Trinity::Git.create_build_branch(date)
        version = Trinity::Redmine.create_version(project_name, build)
        logmsg :info, "Created new build branch #{build_name}"
        `git push origin #{build_name}`
        return build
      else
        logmsg :info, "We have build #{build}"

        version = Trinity::Redmine::Version.find_version(project_name, build)

        if version.nil?
          version = Trinity::Redmine.create_version(project_name, build)
        end

        logmsg :info, "Found version: #{version.name}"

        if version.nil?
          logmsg :fatal, 'No version found or loaded'
          abort
        end

        # Updating version URL
        build_suffix = @config['transitions'][project_name]['config']['build_suffix']
        cf_build_url = version.get_cf(18) # Get version URL Custom field
        if !cf_build_url.value.nil?
          cf_build_url.value = "http://#{build}#{build_suffix}"
          Trinity::Redmine::Version.prefix = '/'
          version.save
        end

        `git push origin #{build}`

        build_hash = `git rev-parse origin/#{build}`.to_s
        master_hash = `git rev-parse origin/#{@master_branch}`.to_s

        `git checkout #{@master_branch}`

        if (`git branch -r --merged`.split("\n").map { |n| n.strip.gsub('* ', '') }.include?('origin/'+build)) && (build_hash.eql? master_hash)

          logmsg :info, "Build #{build} is NOT MERGED to master. Switching to #{build} and start merging features"
          `git checkout #{build}`
        else
          logmsg :info, " Branch #{build} is merged to #{@master_branch}"

          `git branch -d #{build}`

          build = Trinity::Git.create_build_branch(date)
          logmsg :info, "Created new build branch: #{build}"

          return build
        end


        #build_pushed = Trinity::Git.is_branch_pushed(build)
        #logmsg :info, "Check if build is pushed to origin: #{build_pushed.inspect}"
        #
        #build_merged = Trinity::Git.is_branch_merged(build, @master_branch)
        #logmsg :info, "Check if build is already merged: #{build_merged.inspect}"
        #
        #build_has_no_issues = Trinity::Redmine.fetch_issues({:project_id => project_name, :fixed_version_id => version.id.to_i}).count.eql? 0
        #logmsg :warn, "Build has NO issues: #{build_has_no_issues.inspect}"

        #if build_pushed
        #
        #  logmsg :info, 'Build pushed to origin'
        #
        #  if Trinity::Git.hash_eql("origin/#{build}", "origin/#{@master_branch}")
        #    # New empty build
        #    logmsg :info, "Build #{build} has no issues. Switching to #{build} and start merging features"
        #    `git checkout #{build}`
        #  elsif !Trinity::Git.hash_eql("origin/#{build}", "origin/#{@master_branch}")
        #
        #  end
        #
        #  if build_merged and build_has_no_issues
        #
        #  elsif !build_merged
        #    # New empty build
        #    logmsg :info, "Build #{build} is NOT MERGED to master. Switching to #{build} and start merging features"
        #    `git checkout #{build}`
        #  else
        #    logmsg :info, "Build #{build} is MERGED to master and PUSHED to origin"
        #
        #    `git branch -d #{build}`
        #    logmsg :info, "Deleted build branch #{build}"
        #
        #    build = Trinity::Git.create_build_branch(date)
        #    logmsg :info, "Created new build branch: #{build}"
        #
        #    return build
        #  end
        #
        #else
        #  logmsg :info, 'Build NOT pushed to origin. Now pushing'
        #  `git push origin #{build}`
        #end

        #time_to_qa = time_to_qa(build, options[:hours_to_qa])
        #
        #logmsg :info, "Is it time to QA build?: #{time_to_qa}"
        #
        #if time_to_qa
        #  logmsg :info, 'Time to QA build.'
        #
        #  `git push origin #{build}`
        #  `git checkout master`
        #  `git branch -D #{build}`
        #
        #  logmsg :info, "Deleted branch #{build}"
        #
        #  message = "Build <a href='http://r.itcreativoff.com/versions/#{version.id}'>#{build}</a>
        #             is ready for QA"
        #
        #  notify('qa', message)
        #else
        #  `git checkout #{build}`
        #end

        log_block('Prepare', 'end')
        #`git checkout #{build}`
        return build
      end

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
        logmsg :error, "#{__method__}: Chronic.parse error"
        abort
      end

      #logmsg :info, "Date for build: #{date}; Hours to QA: #{options[:hours_to_qa]}"
      return date
    end

    def time_to_qa(build, hours_diff)

      #logmsg :info, "Hours diff: #{hours_diff}"
      #logmsg :info, "Build: #{build}"

      # Parse date from build name
      buf = build.split('_').drop(1)
      date_buf = buf.take(3).join('-').concat ' '
      time_buf = buf.last
      date_string = date_buf.concat(time_buf)
      parsed_date = Chronic.parse(date_string)

      if parsed_date.nil?
        logmsg :fatal, "#{__method__} couldn't parse time"
        abort
      end

      logmsg :info, "#{__method__}: #{parsed_date}"

      (parsed_date-Time.now)/3600.round <= hours_diff
    end

    def log_block(name, state)
      logmsg :info, "[============================= #{name}: #{state} ===============================]"
    end

    # Notify all recipients of the given condition with the specified message.
    #
    # notify - The Condition.
    # message   - The String message to send.
    #
    # Returns nothing.
    def notify(notify, message)

      spec = Contact.normalize(notify)
      unmatched = []

      # Resolve contacts.
      resolved_contacts =
          spec[:contacts].inject([]) do |acc, contact_name_or_group|
            cons = Array(Trinity.contacts[contact_name_or_group] || Trinity.contact_groups[contact_name_or_group])
            unmatched << contact_name_or_group if cons.empty?
            acc += cons
            acc
          end

      # Warn about unmatched contacts.
      unless unmatched.empty?
        msg = "no matching contacts for '#{unmatched.join(", ")}'"
        logmsg(:warn, msg)
      end

      # Notify each contact.
      resolved_contacts.each do |c|
        host = `hostname`.chomp rescue 'none'
        begin
          c.notify(message, Time.now, spec[:priority], spec[:category], host)
          msg = "#{c.info ? c.info : "notification sent for contact: #{c.name}"}"
          logmsg(:info, msg % [])
        rescue Exception => e
          logmsg(:error, "#{e.message} #{e.backtrace}")
          msg = "Failed to deliver notification for contact: #{c.name}"
          logmsg(:error, msg % [])
        end
      end
    end

    private

    def is_conflict(merge_message, meta=[])
      logmsg :warn, merge_message
      conflict_pattern = /CONFLICT|fatal/

      if !conflict_pattern.match(merge_message)
        return false
      end

      message = "
      WARNING!!! Conflict while merging branches.\r\n
      You have to manually merge branches.\r\n

      #{meta}

      #{merge_message}

      "

      notify('admins', message)

      return true
    end

    def read_git_flow_config
      @master_branch = Trinity::Git.config('gitflow.branch.master')
      @develop_branch = Trinity::Git.config('gitflow.branch.develop')

      if @master_branch.nil? or @develop_branch.nil?
        notify('admins', "Error getting git flow config branches: master_branch:#{@master_branch.inspect}, develop_branch:#{@develop_branch.inspect}")
      end
    end

  end
end