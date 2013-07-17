module Trinity
  class RestAPI < ActiveResource::Base
    self.site = 'http://r.itcreativoff.com'
    self.user = 'trinity'
    self.password = 'trinity'
    self.format = :xml
  end
end