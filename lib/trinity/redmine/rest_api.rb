module Trinity
  module Redmine
    class RestAPI < ActiveResource::Base
      self.site = 'http://r.itcreativoff.com'
      self.user = 'trinity'
      self.password = 'trinity'
      self.format = :xml
    end
  end
end