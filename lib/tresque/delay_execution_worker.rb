module TResque
  class DelayExecutionWorker
    include ::TResque::Worker
    inputs :class_name, :id, :method_name, :args

    # enabled both of these by option
    extend ::TResque::WorkerLock
    extend ::TResque::QueueLock

    class << self
      # handle dynamic locks
      def get_lock_namespace(options)
        options["lock_namespace"] || options["class_name"]
      end

      def get_queue_lock_attributes(options)
        return nil unless options["queue_lock"]
        [options["queue_lock"]].flatten
      end

      def get_worker_lock_attributes(options)
        return nil unless options["worker_lock"]
        [options["worker_lock"]].flatten
      end
    end

    def work
      return unless record
      if args.nil? || args.empty?
        record.send(self.method_name)
      else
        record.send(self.method_name, *self.args)
      end
    end

    protected

    def klass
      @klass ||= class_name.constantize
    end

    def record
      @record ||= if id.nil?
        klass
      else
        if klass.respond_to?(:find_by)
          klass.find_by(id: id)
        elsif klass.respond_to?(:find_by_id)
          klass.find_by_id(id)
        else
          klass.find(id)
        end
      end
    end


  end
end
