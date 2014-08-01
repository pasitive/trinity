module Trinity
  module Redmine
    class RestAPI < ActiveResource::Base

      # Getting custom fieled
      def get_cf(id=nil)
        unless self.respond_to? 'custom_fields'
          raise NoSuchCustomFieldError.new("No custom fields")
          #logmsg :warn, "Version #{self.id} have no custom field with id=#{id}"
        end

        return self.custom_fields if id.nil?

        cf = self.custom_fields.select { |i| i.id.to_i.eql? id }.first
        cf
      end

    end
  end
end