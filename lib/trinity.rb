#!/usr/bin/env ruby
# encoding: utf-8

require 'rake'
require 'yaml'
require 'chronic'
require 'mail'
require 'thor'
require 'trinity/errors'
require 'trinity/git'
require 'trinity/redmine'
require 'trinity/version'
require 'trinity/config'
require 'trinity/cli'

CONTACT_DEPS = {}
CONTACT_LOAD_SUCCESS = {}
TRANSITION_LOAD_SUCCESS = {}

def load_contact(name)
  require "trinity/contacts/#{name}"
  CONTACT_LOAD_SUCCESS[name] = true
rescue LoadError
  CONTACT_LOAD_SUCCESS[name] = false
end

require 'trinity/contact'
load_contact(:jabber)

require 'trinity/transition'
require 'trinity/transitions/assign_to_author'
require 'trinity/transitions/not_assigned_with_commits'
require 'trinity/transitions/time_to_qa'
require 'trinity/transitions/rejected_with_commits'

# App wide logging system
LOG = Logger.new(STDOUT)

def applog(level, text)
  case level
    when :info
      LOG.info text
    when :error
      LOG.error text
    when :fatal
      LOG.fatal text
    when :debug
      LOG.debug text
    when :warn
      LOG.warn text
    else
      LOG.info text
  end
end

module Trinity

  class << self
    # internal
    attr_accessor :inited,
                  :contacts,
                  :contact_groups
  end

  # Initialize internal data.
  #
  # Returns nothing.
  def self.internal_init
    # Only do this once.
    return if self.inited

    # Variable init.
    self.contacts = {}
    self.contact_groups = {}

    # Additional setup.
    self.setup

    # Init has been executed.
    self.inited = true
  end

  def self.setup

  end

  # Instantiate a new Contact of the given kind and send it to the block.
  # Then prepare, validate, and record the Contact. Aborts on invalid kind,
  # duplicate contact name, invalid contact, or conflicting group name.
  #
  # kind - The Symbol contact class specifier.
  #
  # Returns nothing.
  def self.contact(kind)
    # Ensure internal init has run.
    self.internal_init

    # Verify contact has been loaded.
    if CONTACT_LOAD_SUCCESS[kind] == false
      applog(:error, "A required dependency for the #{kind} contact is unavailable.")
      applog(:error, "Run the following commands to install the dependencies:")
      CONTACT_DEPS[kind].each do |d|
        applog(:error, "  [sudo] gem install #{d}")
      end
      abort
    end

    # Create the contact.
    begin
      c = Contact.generate(kind)
    rescue NoSuchContactError => e
      abort e.message
    end

    # Send to block so config can set attributes.
    yield(c) if block_given?

    # Call prepare on the contact.
    #c.prepare

    # Remove existing contacts of same name.
    existing_contact = self.contacts[c.name]
    if existing_contact
      self.uncontact(existing_contact)
    end

    # Warn and noop if the contact has been defined before.
    if self.contacts[c.name] || self.contact_groups[c.name]
      applog(:warn, "Contact name '#{c.name}' already used for a Contact or Contact Group")
      return
    end

    # Abort if the Contact is invalid, the Contact will have printed out its
    # own error messages by now.
    unless Contact.valid?(c) && c.valid?
      abort 'Exiting on invalid contact'
    end

    # Add to list of contacts.
    self.contacts[c.name] = c

    # Add to contact group if specified.
    if c.group
      # Ensure group name hasn't been used for a contact already.
      if self.contacts[c.group]
        abort "Contact Group name '#{c.group}' already used for a Contact"
      end

      self.contact_groups[c.group] ||= []
      self.contact_groups[c.group] << c
    end
  end

  # Remove the given contact from god.
  #
  # contact - The Contact to remove.
  #
  # Returns nothing.
  def self.uncontact(contact)
    self.contacts.delete(contact.name)
    if contact.group
      self.contact_groups[contact.group].delete(contact)
    end
  end

end


