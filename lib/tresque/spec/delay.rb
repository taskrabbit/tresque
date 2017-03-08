module TResque
  module Spec
    module Delay

      def delay_object
        TResque::Delay::InvocationProxy.any_instance
      end

      def without_delay
        return yield unless Rails.env.test?
        
        q   = ENV['QUEUE']
        qs  = ENV['QUEUES']

        ENV['QUEUE']  = "v3_default"
        ENV['QUEUES'] = nil

        yield

      ensure
        ENV['QUEUE']  = q
        ENV['QUEUES'] = qs
      end

    end
  end
end