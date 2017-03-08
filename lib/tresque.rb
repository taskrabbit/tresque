require "tresque/version"
require 'resque'

module TResque
  autoload :Util,                     'tresque/util'
  autoload :Worker,                   'tresque/worker'
  autoload :Delay,                    'tresque/delay'
  autoload :DelayExecutionWorker,     'tresque/delay_execution_worker'
  autoload :WorkerLock,               'tresque/worker_lock'
  autoload :QueueLock,                'tresque/queue_lock'
  autoload :Registry,                 'tresque/registry'
  
  module Spec
    autoload :Delay,                  'tresque/spec/delay'
  end
  
  class << self
    def register(app_key, &block)
      registry = ::TResque::Registry.new(app_key)
      registry.instance_eval(&block)
      registry
    end
  end
end
