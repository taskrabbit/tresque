module TResque
  # If you want only one instance of your job running at a time,
  # extend it with this module.
  module WorkerLock

    # Override in your job to control the worker lock experiation time. This
    # is the time in seconds that the lock should be considered valid. The
    # default is one hour (3600 seconds).
    def worker_lock_timeout
      3600
    end

    # Override in your job to control the workers lock key.
    # def worker_lock_key(options)
    #  "#{name}-#{options.to_s}"
    # end

    # Called with the job options before perform.
    # If it raises Resque::Job::DontPerform, the job is aborted.
    def before_perform_worker_lock(options)
      val = worker_lock_key(options)
      if val
        key = "workerslock:#{val}"
        if Resque.redis.setnx(key, true)
          Resque.redis.expire(key, worker_lock_timeout)
        else
          obj = self.new(options)
          obj.requeue!
        end
      end
    end

    def clear_worker_lock(options)
      val = worker_lock_key(options)
      if val
        Resque.redis.del("workerslock:#{val}")
      end
    end

    def around_perform_worker_lock(options)
      yield
    ensure
      # Clear the lock. (even with errors)
      clear_worker_lock(options)
    end

    def on_failure_worker_lock(exception, options)
      # Clear the lock on DirtyExit
      clear_worker_lock(options)
    end

  end
end