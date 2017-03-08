require 'rspec/core'
require 'rspec/expectations'
require 'rspec/mocks'

module InQueueHelper
  def self.extended(klass)
    klass.instance_eval do
      self.queue_name = nil
      chain :in do |queue_name|
        self.queue_name = queue_name
      end
    end
  end

  private

  attr_accessor :queue_name

  def queue(actual)
    if @queue_name
      ResqueSpec.queue_by_name(@queue_name)
    else
      ResqueSpec.queue_for(actual)
    end
  end

end

RSpec::Matchers.define :have_queued do |*expected_args|
  extend InQueueHelper
  include InQueueHelper
  chain :times do |num_times_queued|
    @times = num_times_queued
    @times_info = @times == 1 ? ' once' : " #{@times} times"
  end

  chain :once do |num_times_queued|
    @times = 1
    @times_info = ' once'
  end

  match do |actual|
    matched = queue(actual).select do |entry|
      klass = entry.fetch(:class)
      args = entry.fetch(:args)

      if expected_args.length == 0
        klass.to_s == actual.to_s
      elsif expected_args.length == 1 && expected_args[0].is_a?(Hash) && !expected_args[0].has_key?('tz') && !expected_args[0].has_key?('locale')
        klass.to_s == actual.to_s && args[0].except('locale', 'tz') == expected_args[0]
      else
        klass.to_s == actual.to_s && expected_args == args
      end
    end

    if @times
      matched.size == @times
    else
      matched.size > 0
    end
  end

  failure_message do |actual|
    "expected that #{actual} would have [#{expected_args.join(', ')}] queued#{@times_info}"
  end

  failure_message_when_negated do |actual|
    "expected that #{actual} would not have [#{expected_args.join(', ')}] queued#{@times_info}"
  end

  description do
    "have queued arguments of [#{expected_args.join(', ')}]#{@times_info}"
  end
end

RSpec::Matchers.define :have_queue_size_of do |size|
  extend InQueueHelper
  include InQueueHelper

  match do |actual|
    queue(actual).size == size
  end

  failure_message do |actual|
    "expected that #{actual} would have #{size} entries queued, but got #{queue(actual).size} instead"
  end

  failure_message_when_negated do |actual|
    "expected that #{actual} would not have #{size} entries queued, but got #{queue(actual).size} instead"
  end

  description do
    "have a queue size of #{size}"
  end
end

RSpec::Matchers.define :have_queue_size_of_at_least do |size|
  extend InQueueHelper
  include InQueueHelper
  match do |actual|
    queue(actual).size >= size
  end

  failure_message do |actual|
    "expected that #{actual} would have at least #{size} entries queued, but got #{queue(actual).size} instead"
  end

  failure_message_when_negated do |actual|
    "expected that #{actual} would not have at least #{size} entries queued, but got #{queue(actual).size} instead"
  end

  description do
    "have a queue size of at least #{size}"
  end
end

module ScheduleQueueHelper
  def self.extended(klass)
    klass.instance_eval do
      self.queue_name = nil
      chain :queue do |queue_name|
        self.queue_name = queue_name
      end
    end
  end

  attr_accessor :queue_name

  def schedule_queue_for(actual)
    if @queue_name
      ResqueSpec.queue_by_name(@queue_name)
    else
      ResqueSpec.schedule_for(actual)
    end
  end

end

RSpec::Matchers.define :have_scheduled do |*expected_args|
  extend ScheduleQueueHelper
  include ScheduleQueueHelper
  chain :at do |timestamp|
    @interval = nil
    @time = timestamp
    @time_info = "at #{@time}"
  end

  chain :in do |interval|
    @time = nil
    @interval = interval
    @time_info = "in #{@interval} seconds"
  end

  match do |actual|
    schedule_queue_for(actual).any? do |entry|
      class_matches = entry[:class].to_s == actual.to_s
      args_match = begin
        if expected_args.length == 1 && expected_args[0].is_a?(Hash) && !expected_args[0].has_key?('tz') && !expected_args[0].has_key?('locale')
          entry[:args][0].except('tz', 'locale') == expected_args[0]
        else
          entry[:args] == expected_args
        end
      end

      time_matches = if @time
        entry[:time] == @time
      elsif @interval
        entry[:time].to_i == (entry[:stored_at] + @interval).to_i
      else
        true
      end

      class_matches && args_match && time_matches
    end
  end

  failure_message do |actual|
    ["expected that #{actual} would have [#{expected_args.join(', ')}] scheduled", @time_info].join(' ')
  end

  failure_message_when_negated do |actual|
    ["expected that #{actual} would not have [#{expected_args.join(', ')}] scheduled", @time_info].join(' ')
  end

  description do
    "have scheduled arguments"
  end
end

RSpec::Matchers.define :have_scheduled_at do |*expected_args|
  extend ScheduleQueueHelper
  warn "DEPRECATION WARNING: have_scheduled_at(time, *args) is deprecated and will be removed in future. Please use have_scheduled(*args).at(time) instead."

  match do |actual|
    time = expected_args.first
    other_args = expected_args[1..-1]
    schedule_queue_for(actual).any? { |entry| entry[:class].to_s == actual.to_s && entry[:time] == time && other_args == entry[:args] }
  end

  failure_message do |actual|
    "expected that #{actual} would have [#{expected_args.join(', ')}] scheduled"
  end

  failure_message_when_negated do |actual|
    "expected that #{actual} would not have [#{expected_args.join(', ')}] scheduled"
  end

  description do
    "have scheduled at the given time the arguments"
  end
end

RSpec::Matchers.define :have_schedule_size_of do |size|
  extend ScheduleQueueHelper

  match do |actual|
    schedule_queue_for(actual).size == size
  end

  failure_message do |actual|
    "expected that #{actual} would have #{size} scheduled entries, but got #{schedule_queue_for(actual).size} instead"
  end

  failure_message_when_negated do |actual|
    "expected that #{actual} would have #{size} scheduled entries."
  end

  description do
    "have schedule size of #{size}"
  end
end

RSpec::Matchers.define :have_schedule_size_of_at_least do |size|
  extend ScheduleQueueHelper

  match do |actual|
    schedule_queue_for(actual).size >= size
  end

  failure_message do |actual|
    "expected that #{actual} would have at least #{size} scheduled entries, but got #{schedule_queue_for(actual).size} instead"
  end

  failure_message_when_negated do |actual|
    "expected that #{actual} would have at least #{size} scheduled entries."
  end

  description do
    "have schedule size of #{size}"
  end
end


RSpec::Matchers.define :have_delayed do |method_name|
  extend InQueueHelper
  include InQueueHelper

  chain :until do |timestamp|
    @when = timestamp.to_i
  end

  chain :with do |*args|
    @args = args
  end

  chain :in_lock_namespace do |ns|
    @lock_namespace = ns.to_s
  end

  chain :with_queue_lock do |lock|
    @queue_lock = lock.to_s
  end

  chain :with_worker_lock do |lock|
    @worker_lock = lock.to_s
  end

  match do |class_name|

    class_name = case class_name
    when Class
      class_name.name
    when String, Symbol
      class_name
    else # instances of objects
      class_name.class.name
    end

    [@queue_name || ResqueSpec.queues].flatten.compact.each do |queue|
      ResqueSpec.queue_by_name(queue).detect do |entry|
        klass = entry[:class]
        args  = entry[:args]
        data  = args.first if args.is_a?(Array)

        matched =   data['class_name'] == class_name.to_s
        matched &&= data['method_name'] == method_name.to_s
        matched &&= data['run_at'] == @when                   if @when
        matched &&= data['args'] == @args                     if @args
        matched &&= data['lock_namespace'] == @lock_namespace if @lock_namespace
        matched &&= data['queue_lock'] == @queue_lock         if @queue_lock
        matched &&= data['worker_lock'] == @worker_lock       if @worker_lock
        matched
      end
    end
  end

  failure_message do |actual|
    "expected that #{method_name} would have been a delayed invocation"
  end

  failure_message_when_negated do |actual|
    "expected that #{method_name} would not have been delayed"
  end

  description do
    "#{method_name} should be deplayed"
  end
end
