module TResque
  module Delay
    extend ::ActiveSupport::Concern

    module ClassMethods

      def delay(options = {})
        InvocationProxy.new(self, options)
      end


      def async(method_name, options = {})
        raise "Attempted to handle #{self.name}##{method_name} asyncronously but #{method_name} was not yet defined" unless (self.instance_methods + self.private_instance_methods).include?(method_name)

        class_eval <<-EV, __FILE__, __LINE__ + 1
          def #{method_name}_with_delay(*args)
            self.delay(#{options.inspect}).#{method_name}_without_delay(*args)
          end
          alias_method_chain :#{method_name}, :delay
        EV
      end

    end

    def delay(options = {})
      InvocationProxy.new(self, options)
    end


    def method_missing(method_name, *args)
      if method_name.to_s =~ /^delay__(.+)$/
        self.delay.send($1, *args)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      method_name.to_s =~ /^delay__(.+)/ || super
    end


    class InvocationProxy

      def initialize(object, options = {})

        @object = object
        @run_at = options[:run_at]
        @run_at ||= (!!options[:force] ? true : nil)
        @synchronous = !!options[:synchronous]

        @queue_namespace  = options[:queue_namespace] || Util.calculate_namespace_from_class(object)
        @queue_name       = options[:queue] || 'default'

        @lock_namespace   = options[:lock_namespace]
        @queue_lock_key   = options[:queue_lock_key]
        @worker_lock_key  = options[:worker_lock_key]
      end

      def method_missing(method_name, *args)
        if !@synchronous && (!in_resque? || @run_at == true || @run_at.to_i > Time.now.to_i)
          @method_name = method_name.to_s
          @args = args
          queue_delayed_invocation!
        else
          @object.send(method_name, *args)
        end
      end

      def respond_to?(*args)
        return true unless in_resque?
        @object.respond_to?(*args)
      end

      protected

      def in_resque?
        !!(ENV['QUEUE'] || ENV['QUEUES'])
      end

      def queue_delayed_invocation!
        push = {}

        if @object.is_a?(Class)
          push["class_name"] = @object.name
        else
          push["class_name"] = @object.class.name
          push["id"] = @object.respond_to?(:delay_id) ? @object.delay_id : @object.id
        end

        push["method_name"]     = @method_name
        push["args"]            = @args
        push["queue_namespace"] = @queue_namespace
        push["queue"]           = @queue_name
        push["run_at"]          = @run_at             if @run_at && @run_at != true
        push["lock_namespace"]  = @lock_namespace     if @lock_namespace

        if @queue_lock_key
          push["queue_lock"]          = @queue_lock_key.to_s
          push[@queue_lock_key.to_s]  = push["id"]
        end

        if @worker_lock_key
          push["worker_lock"]         = @worker_lock_key.to_s
          push[@worker_lock_key.to_s] = push["id"]
        end

        TResque::DelayExecutionWorker.enqueue(push)
      end

    end


  end
end
