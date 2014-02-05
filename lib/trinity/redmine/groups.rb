module Trinity
  module Redmine
    class Groups < RestAPI

      class << self

        def get_group_users(group_id)
          valid = true
          group = Trinity::Redmine::Groups.find(group_id, :params => {:include => 'users'})

          if !group.respond_to? 'name'
            logmsg(:warn, "Group with ID ##{group_id} not found")
            valid = false
          end

          if valid && (!group.respond_to? 'users')
            logmsg(:warn, "No users in group #{group.name}")
            valid = false
          end

          group_users = group.users.inject([]) do |result, user|
            result << user.id.to_i
            result
          end

          if valid && group_users.empty?
            logmsg(:warn, "No users in group #{group.name}")
            valid = false
          end

          return [] if !valid

          group_users
        end

      end

    end
  end
end