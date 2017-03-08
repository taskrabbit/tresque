module TResque
  # If you want only one instance of your job queued at a time,
  # extend it with this module.
  module QueueLock

    # Override in your job to control the lock experiation time. This is the
    # time in seconds that the lock should be considered valid. The default
    # is one hour (3600 seconds).
    def queue_lock_timeout
      3600
    end

    # Override in your job to control the lock key. It is
    # passed the same arguments as `perform`, that is, your job's
    # payload.
    #def queue_lock_key(options)
    #  "#{name}-#{options.to_s}"
    #end    

    # See the documentation for SETNX http://redis.io/commands/setnx for an
    # explanation of this deadlock free locking pattern
    def before_enqueue_queue_lock(options)
      val = queue_lock_key(options)
      if val
        key = "lock:#{val}"
        now = Time.now.to_i
        from_now = queue_lock_timeout + 1
        key_expire = from_now + 600 # some exra time
        timeout = now + from_now

        # return true if we successfully acquired the lock
        if Resque.redis.setnx(key, timeout)
          # expire in case of error to make sure it goes away
          Resque.redis.expire(key, key_expire)
          return true
        end

        # see if the existing timeout is still valid and return false if it is
        # (we cannot acquire the lock during the timeout period)
        return false if now <= Resque.redis.get(key).to_i

        # otherwise set the timeout and ensure that no other worker has
        # acquired the lock
        if now > Resque.redis.getset(key, timeout).to_i
          # expire in case of error to make sure it goes away
          Resque.redis.expire(key, key_expire)
          return true
        else
          return false
        end

      end
    end

    def clear_queue_lock(options)
      val = queue_lock_key(options)
      if val
        Resque.redis.del("lock:#{val}")
      end
    end

    def before_perform_queue_lock(options)
      clear_queue_lock(options)
    end

    def after_dequeue_queue_lock(options)
      clear_queue_lock(options)
    end
  end
end
