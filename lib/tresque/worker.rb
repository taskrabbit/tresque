require 'resque-retry'
require 'digest/sha1'

module TResque
  module Worker
    extend ::ActiveSupport::Concern

    mattr_accessor :skip_check_queues

    included do
      extend ::Resque::Plugins::ExponentialBackoff
      TResque::Registry.worker(self)
    end

    module ClassMethods
      def queue(name=nil)
        return @requeue_in_queue if !name && @requeue_in_queue
        return @queue if !name && @queue
        name ||= :default
        full_queue("#{app_key}_#{name}")
      end

      def full_queue(name)
        @queue = name.to_s
      end

      def application(app_key)
        @app_key = Util.normalize(app_key)
      end

      def app_key
        return @app_key if @app_key
        @app_key = Util.calculate_namespace_from_class(self)
      end

      def enqueue(options = {})
        options = options.with_indifferent_access

        options[:locale] ||= I18n.locale.to_s
        options[:tz]     ||= Time.zone.name

        run_at = options.delete(:run_at)
        if options[:full_queue]
          queue_name = options[:full_queue]
        elsif options[:queue] || options[:queue_namespace]
          namespace = options[:queue_namespace] || self.app_key
          queue = options[:queue] || "default"
          queue_name = "#{namespace}_#{queue}"
        else
          queue_name = self.queue
        end

        if queue_name == "t_resque_default"
          message = "QUEUE_ERROR (#{self.class.name}): #{queue_name} will not be worked!"
          Rails.logger.error(message)
          puts message if Rails.env.test?
        end

        if !TResque::Worker.skip_check_queues && !TResque::Registry.queues.include?(queue_name)
          message = "QUEUE_ERROR (#{self.class.name}): #{queue_name} will not be worked!"
          Rails.logger.error(message)
          puts message if Rails.env.test?
        end

        options[:full_queue] = queue_name
        if run_at
          Resque.enqueue_at_with_queue(queue_name, run_at, self, options)
        else
          Resque.enqueue_to(queue_name, self, options)
        end

        # too many events
        # QueueBus.publish_log(:worker_enqueued, {
        #   options: options,
        #   queue_name:  queue_name,
        #   worker_name: self.name.to_s,
        #   run_at: run_at.to_i
        # }) unless Rails.env.test?

        options
      end

      def perform(options)
        Waistband.clear_logs if Waistband.config.logging

        @previous_locale, @previous_zone = I18n.locale, Time.zone

        options = options.with_indifferent_access
        obj = self.new(options.except(:locale, :tz, :bus_locale, :bus_timezone))

        locale = obj.respond_to?(:calculate_locale, true) ? obj.send(:calculate_locale) : nil
        locale ||= options[:locale]
        locale ||= options[:bus_locale]
        locale ||= I18n.locale if Rails.env.production?  # don't crash in production, use default

        zone = obj.respond_to?(:calculate_timezone, true) ? obj.send(:calculate_timezone) : nil
        zone ||= options[:tz]
        zone ||= options[:bus_timezone]

        I18n.locale = locale
        Time.zone   = zone

        # too many events
        # QueueBus.publish_log(:worker_perform, {
        #   options: options,
        #   worker_name: self.name.to_s,
        #   locale:  locale,
        #   time_zone: zone
        # }) unless Rails.env.test?

        obj.worker_perform
      rescue Resque::Job::DontPerform
        # it's cool
      ensure
        # write waistband logs
        Waistband.write_logs(nil) if Waistband.config.logging
        # reset
        I18n.locale, Time.zone = @previous_locale, @previous_zone
      end

      def inputs(*args)
        args.each do |name|
          define_method name do
            enqueued_options[name]
          end
        end
      end
      alias_method :input, :inputs

      def turn_retry_off
        @retry_limit = 0
      end

      def lock_namespace(val)
        @lock_namespace = val.to_s
      end

      def worker_lock(*args)
        raise ("worker_lock: what should i lock on?") if args.size == 0
        extend ::TResque::WorkerLock
        @worker_lock_attributes = args.collect(&:to_s)
      end

      def queue_lock(*args)
        raise ("queue_lock: what should i lock on?") if args.size == 0
        extend ::TResque::QueueLock
        @queue_lock_attributes = args.collect(&:to_s)
      end

      def get_lock_namespace(options)
        @lock_namespace ||= self.name
      end

      def get_queue_lock_attributes(options)
        @queue_lock_attributes  ||= []
      end

      def get_worker_lock_attributes(options)
        @worker_lock_attributes ||= []
      end

      def queue_lock_key(options)
        options_lock_key(options, get_queue_lock_attributes(options))
      end

      def worker_lock_key(options)
        options_lock_key(options, get_worker_lock_attributes(options))
      end

      def options_lock_key(options, keys)
        return nil unless keys  # not actually locking

        keys = ["all"] if keys.size == 0
        keys = options.keys if keys.size == 1 && keys.first == "all"
        keys.sort!

        vals = [get_lock_namespace(options)]
        keys.each do |key|
          vals << key
          vals << options[key].to_s
        end
        Digest::SHA1.hexdigest(vals.join("-"))
      end

      # make sure we put it back in the same queue
      # @failure_hooks_already_ran on https://github.com/defunkt/resque/tree/1-x-stable
      # to prevent running twice
      def on_failure_aaa(exception, *args)
        # note: sorted alphabetically
        # queue needs to be set for rety to work (know what queue in Requeue.class_to_queue)
        @requeue_in_queue = args[0]["full_queue"]
      end

      def on_failure_zzz(exception, *args)
        # note: sorted alphabetically
        @requeue_in_queue = nil
      end
    end

    attr_reader :enqueued_options
    def initialize(options = {})
      @enqueued_options = options.with_indifferent_access
    end

    def worker_perform
      to_call = self.enqueued_options[:action] || :work
      send(to_call)
    end

    def requeue_delay_seconds
      1
    end

    def requeue
      self.enqueued_options["run_at"] = nil
      delay = self.requeue_delay_seconds
      if delay > 0
        self.enqueued_options["run_at"] = delay.seconds.from_now
      end
      self.class.enqueue(self.enqueued_options)
    end

    def requeue!
      requeue
      raise Resque::Job::DontPerform
    end
  end
end
