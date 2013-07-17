require 'daemons'
require 'rake'
require 'yaml'
require 'trinity/git'
require 'trinity/redmine'
require 'trinity/version'
require 'chronic'
require 'mail'
require 'thor'



MAIL_NOTICE_HASH = %w(db@happylab.ru i.brissiuk@gmail.com)

require 'trinity/cli'
