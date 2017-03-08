module TResque
  module Util
    extend self

    def normalize(val)
      val.to_s.gsub(/\W/, "_").downcase
    end
    
    def calculate_namespace_from_class(klass)
      klass = klass.class unless klass.is_a?(Class)
      pieces = klass.name.to_s.split("::")
      return "worker" if pieces.size < 2
      pieces.first.underscore
    end
  end
end