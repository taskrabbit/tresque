require 'tresque/resque_spec/ext'
require 'tresque/resque_spec/helpers'
require 'tresque/resque_spec/matchers'

module ResqueSpec

  # methods to be made accessible for every spec
  module BaseMethods

    def run_resque_workers(options = {})
      quantity = options.fetch(:quantity, 1)

      quantity.times do
        ResqueSpec.perform_all!
      end
    end

  end


  include ::Resque::Helpers
  extend self

  attr_accessor :inline
  attr_accessor :disable_ext

  def dequeue(queue_name, klass, *args)
    queue_by_name(queue_name).delete_if do |job|
      job[:class] == klass.to_s && args.empty? || job[:args] == args
    end
  end

  def enqueue(queue_name, klass, *args)
    perform_or_store(queue_name, :class => klass.to_s, :args => args)
  end

  def perform_next(queue_name)
    perform(queue_name, shift_queue(queue_name))
  end

  def perform_all(queue_name)
    while job = shift_queue(queue_name)
      perform(queue_name, job)
    end
  end

  def shift_queue(queue_name)
    # pass scheduled ones
    array = queue_by_name(queue_name) || []
    index = nil
    array.each_with_index do |hash, i|
      if hash[:time].to_i <= Time.now.to_i
        index = i
        break
      end
    end
    return nil unless index
    array.delete_at(index)
  end

  def pop(queue_name)
    return unless payload = shift_queue(queue_name)
    new_job(queue_name, payload)
  end

  def queue_by_name(name)
    queues[name.to_s]
  end

  def queue_for(klass)
    queue_by_name(queue_name(klass))
  end

  def peek(queue_name, start = 0, count = 1)
    queue_by_name(queue_name).slice(start, count)
  end

  def queue_name(klass)
    if klass.is_a?(String)
      klass = Kernel.const_get(klass) rescue nil
    end

    name_from_instance_var(klass) or
      name_from_queue_accessor(klass) or
        raise ::Resque::NoQueueError.new("Jobs must be placed onto a queue.")
  end

  def queues
    @queues ||= Hash.new {|h,k| h[k] = []}
  end

  def delete_all(queue_name)
    queue = "queue:#{queue_name}"
    Resque.redis.del(queue)
    reset!
  end

  def perform_all!
    ::TResque::Registry.queues.each do |queue_name|
      ResqueSpec.perform_all(queue_name)
    end
  end

  # Check if we have queued a delayed worker for `klass` with `*args`
  # Very slow, checks every `delayed` key
  def delayed?(klass, *args)
    klass = klass.to_s unless klass.is_a? String
    [*Resque.redis.keys("delayed:*")].each do |key|
      [*Resque.redis.lrange(key, 0, -1)].each do |item|
        parsed_item = JSON.parse(item)
        return true if parsed_item['class'] == klass && parsed_item['args'] == [*args]
      end
    end

    false
  end

  # Get back the key of the delayed worker if it exists
  def delayed_key(klass, *args)
    klass = klass.to_s unless klass.is_a? String
    [*Resque.redis.keys("delayed:*")].each do |key|
      [*Resque.redis.lrange(key, 0, -1)].each do |item|
        parsed_item = JSON.parse(item)
        return key if parsed_item['class'] == klass && parsed_item['args'] == [*args]
      end
    end

    nil
  end

  # check if the worker has a lock with the provided args
  def locked?(klass, *args)
    klass = klass.to_s unless klass.is_a? String

    key = "lock:#{klass}-#{[*args].join('-')}"
    Resque.redis.keys(key).present?
  end

  def clear_locked!
    [*Resque.redis.keys("lock:*")].each do |key|
      Resque.redis.del(key)
    end
  end

  def clear_all!
    [*Resque.redis.keys].each do |key|
      Resque.redis.del(key)
    end
  end

  def reset!
    clear_all!
    queues.clear
    self.inline = false
  end

  private

  def name_from_instance_var(klass)
    klass.instance_variable_get(:@queue)
  end

  def name_from_queue_accessor(klass)
    klass.respond_to?(:queue) and klass.queue
  end

  def new_job(queue_name, payload)
    Resque::Job.new(queue_name, payload_with_string_keys(payload))
  end

  def perform(queue_name, payload)
    prev = ENV['QUEUE']
    ENV['QUEUE'] = queue_name
    new_job(queue_name, payload).perform
  ensure
    ENV['QUEUE'] = prev
  end

  def perform_or_store(queue_name, payload)
    if inline
      perform(queue_name, payload)
    else
      store(queue_name, payload)
    end
  end

  def store(queue_name, payload)
    queue_by_name(queue_name) << payload
  end

  def payload_with_string_keys(payload)
    {
      'class' => payload[:class],
      'args' => decode(encode(payload[:args])),
      'stored_at' => payload[:stored_at]
    }
  end
end

config = RSpec.configuration
config.include ::ResqueSpec::Helpers
