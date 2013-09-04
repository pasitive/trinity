#!/usr/bin/env ruby

God.watch do |w|
  w.name = "transition"

  w.log = "transition.log"

  w.dir = '/Users/denisboldinov/Desktop/trinity/'
  w.interval = 5

  w.start = "bundle exec trinity transition -vc /Users/denisboldinov/Desktop/trinity/config.yaml"

  w.keepalive

  w.behavior(:clean_pid_file)

  w.transition(:up, :start) do |on|
    on.condition(:process_exits) do |c|
      c.notify = 'admins'
    end
  end

end

God::Contacts::Jabber.defaults do |d|
  d.host = 'talk.google.com'
  d.from_jid = 'support@happylab.ru'
  d.password = 'NK7Ddot3gJDegx'
end

God.contact(:jabber) do |c|
  c.name = 'Denis'
  c.group = 'admins'
  c.to_jid = 'denis.a.boldinov@gmail.com'
end